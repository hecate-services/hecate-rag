%%% @doc Integration tests for the ingest -> embed -> search -> prune
%%% pipeline, and the sources query desks. Direct writes to `rag_store'
%%% (barrel, record mode) — no evoq, no aggregate, no projections.
%%%
%%% Boots the real `hecate_rag' application against real `barrel' storage
%%% and a real `hecate_embed'-equivalent call (barrel's own Ollama
%%% embedder) with the HTTP/health ports overridden to avoid colliding
%%% with any already-running hecate-rag instance on this box.
-module(embed_corpus_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([ingest_embed_search_prune_round_trip/1, sources_query_round_trip/1,
         embed_without_ingest_errors/1, seed_corpus_creates_verbatim_source/1,
         get_document_verbatim_round_trip/1,
         refresh_scheduler_detects_and_refreshes_change/1,
         refresh_scheduler_namespaces_by_repo_to_avoid_collisions/1]).

all() ->
    [ingest_embed_search_prune_round_trip, sources_query_round_trip,
     embed_without_ingest_errors, seed_corpus_creates_verbatim_source,
     get_document_verbatim_round_trip, refresh_scheduler_detects_and_refreshes_change,
     refresh_scheduler_namespaces_by_repo_to_avoid_collisions].

init_per_suite(Config) ->
    ok = rag_test_helpers:start_hecate_rag(),
    Config.

end_per_suite(_Config) ->
    rag_test_helpers:stop_hecate_rag().

ingest_embed_search_prune_round_trip(_Config) ->
    DocId = fresh_id(),
    %% Unique per run: chunk_id is content/source_path-derived, not
    %% document-id-derived, so this is what distinguishes "our" hit.
    SourcePath = <<"quokka-", DocId/binary, ".md">>,
    Content = <<"# The Quokka Habitat\n\nQuokkas are marsupials found "
                "almost exclusively on Rottnest Island off Western "
                "Australia's coast.\n">>,
    {ok, _} = ingest(DocId, SourcePath, Content),
    {ok, #{chunks := N}} = embed(DocId),
    ?assert(N > 0),

    %% Real embedding call (barrel's own Ollama provider), real search —
    %% this is the pipeline that used to be entirely dead. `mode => sync'
    %% on the embedding policy means the write is searchable the instant
    %% put_chunk returns, no polling needed.
    {ok, Hits} = rag_store:search_text(<<"Where do quokkas live?">>, 5),
    ?assert(hit_from_source(Hits, SourcePath)),

    {ok, _} = prune(DocId),
    {ok, GoneHits} = rag_store:search_text(<<"Where do quokkas live?">>, 5),
    ?assertNot(hit_from_source(GoneHits, SourcePath)).

sources_query_round_trip(_Config) ->
    DocId = fresh_id(),
    {ok, _} = ingest(DocId, <<"source-listing-test.md">>, <<"# Hello\n\nWorld.\n">>),

    {ok, Source} = get_source_by_id:handle(DocId),
    ?assertEqual(DocId, maps:get(document_id, Source)),
    ?assertEqual(<<"source-listing-test.md">>, maps:get(source_path, Source)),

    {ok, Page} = list_sources_page:handle(#{}),
    ?assert(lists:any(fun(S) -> maps:get(document_id, S) =:= DocId end, Page)).

embed_without_ingest_errors(_Config) ->
    DocId = fresh_id(),
    Result = maybe_embed_document:embed(#{<<"document_id">> => DocId}),
    ?assertEqual({error, not_ingested}, Result).

%% seed_corpus is the bulk directory-walk path (distinct from ingest/1's
%% per-document one above) — this asserts it now also leaves a verbatim
%% source record per file, not chunks-only, and that re-seeding upserts
%% rather than erroring or duplicating.
seed_corpus_creates_verbatim_source(Config) ->
    SeedId = fresh_id(),
    RelPath = <<"quokka-seed-", SeedId/binary, ".md">>,
    TmpDir = ?config(priv_dir, Config),
    Content = <<"# Quokka Seeding\n\nSeeded straight from a directory "
                "walk, not a per-document upload.\n">>,
    ok = file:write_file(filename:join(TmpDir, RelPath), Content),

    {ok, _Stats} = maybe_seed_corpus:seed(seed_cmd(SeedId, TmpDir)),
    ?assertEqual({ok, #{source_path => RelPath, raw_bytes => Content}},
                 rag_store:get_source_content(RelPath)),

    %% Re-seeding the same file (content unchanged) upserts, not errors.
    {ok, _Stats2} = maybe_seed_corpus:seed(seed_cmd(SeedId, TmpDir)),
    ?assertEqual({ok, #{source_path => RelPath, raw_bytes => Content}},
                 rag_store:get_source_content(RelPath)).

seed_cmd(SeedId, RootDir) ->
    #{<<"seed_id">> => SeedId, <<"root_dir">> => list_to_binary(RootDir),
      <<"glob">> => <<"*.md">>}.

%% get_document_verbatim composes find_source_by_path + get_source_content
%% -- this exercises that composition against a per-document-ingested
%% source (seed_corpus_creates_verbatim_source above already covers the
%% bulk-seeded path into the same underlying storage).
get_document_verbatim_round_trip(_Config) ->
    DocId = fresh_id(),
    SourcePath = <<"verbatim-fetch-", DocId/binary, ".md">>,
    Content = <<"# Verbatim\n\nExact bytes, not a semantic approximation.\n">>,
    {ok, _} = ingest(DocId, SourcePath, Content),

    ?assertEqual({ok, #{source_path => SourcePath, raw_bytes => Content}},
                 get_document_verbatim:handle(SourcePath)),
    ?assertEqual({error, not_found},
                 get_document_verbatim:handle(<<"no-such-path.md">>)).

%% refresh_corpus_scheduler:scan/0 is the internal half of the freshness
%% loop (the external half -- keeping each checkout in sync with git --
%% is corpus_git_sync's own job, not exercised here). Points
%% corpus_repos_config at a fixture repo list naming one fixture dir
%% instead of a real cloned checkout -- scan/0 only reads files off
%% disk, it doesn't care whether git put them there. `path' is never a
%% JSON field, only ever derived (data_dir/corpus/id, see
%% corpus_repos_config:clone_path/1), so the fixture data_dir has to
%% be overridden too, and RepoDir computed the exact same way.
refresh_scheduler_detects_and_refreshes_change(Config) ->
    DocId = fresh_id(),
    RepoId = <<"refresh-repo-", DocId/binary>>,
    RelPath = <<"corpus.md">>,
    TmpDir = ?config(priv_dir, Config),
    DataDir = filename:join(TmpDir, <<"refresh-data-", DocId/binary>>),
    RepoDir = filename:join([DataDir, "corpus", RepoId]),
    ConfigPath = filename:join(TmpDir, <<"refresh-config-", DocId/binary, ".json">>),
    NamespacedId = <<RepoId/binary, "/", RelPath/binary>>,
    ok = filelib:ensure_dir(filename:join(RepoDir, ".")),
    ok = rag_test_helpers:write_repos_config(ConfigPath, [#{id => RepoId, url => <<"unused">>}]),
    ok = application:set_env(hecate_rag, corpus_repos_config, ConfigPath),
    ok = application:set_env(hecate_rag, data_dir, DataDir),

    AbsPath = filename:join(RepoDir, RelPath),
    Original = <<"# Before\n\nOriginal content.\n">>,
    ok = file:write_file(AbsPath, Original),
    ok = refresh_corpus_scheduler:scan(),
    ?assertEqual({ok, #{source_path => NamespacedId, raw_bytes => Original}},
                 rag_store:get_source_content(NamespacedId)),

    %% Unchanged content -- a second scan is a no-op, same content still there.
    ok = refresh_corpus_scheduler:scan(),
    ?assertEqual({ok, #{source_path => NamespacedId, raw_bytes => Original}},
                 rag_store:get_source_content(NamespacedId)),

    %% Changed content -- the next scan picks it up.
    Updated = <<"# After\n\nUpdated content, different bytes.\n">>,
    ok = file:write_file(AbsPath, Updated),
    ok = refresh_corpus_scheduler:scan(),
    ?assertEqual({ok, #{source_path => NamespacedId, raw_bytes => Updated}},
                 rag_store:get_source_content(NamespacedId)),

    ok = application:unset_env(hecate_rag, corpus_repos_config),
    ok = application:unset_env(hecate_rag, data_dir).

%% The real reason document ids get repo-namespaced: two configured
%% repos that both happen to have a same-named file must not collide
%% in rag_store, which keys purely on document_id with no repo scoping
%% of its own.
refresh_scheduler_namespaces_by_repo_to_avoid_collisions(Config) ->
    DocId = fresh_id(),
    RepoA = <<"collide-a-", DocId/binary>>,
    RepoB = <<"collide-b-", DocId/binary>>,
    RelPath = <<"README.md">>,
    TmpDir = ?config(priv_dir, Config),
    DataDir = filename:join(TmpDir, <<"collide-data-", DocId/binary>>),
    DirA = filename:join([DataDir, "corpus", RepoA]),
    DirB = filename:join([DataDir, "corpus", RepoB]),
    ConfigPath = filename:join(TmpDir, <<"collide-config-", DocId/binary, ".json">>),
    ok = filelib:ensure_dir(filename:join(DirA, ".")),
    ok = filelib:ensure_dir(filename:join(DirB, ".")),
    ok = rag_test_helpers:write_repos_config(ConfigPath, [
        #{id => RepoA, url => <<"unused">>},
        #{id => RepoB, url => <<"unused">>}
    ]),
    ok = application:set_env(hecate_rag, corpus_repos_config, ConfigPath),
    ok = application:set_env(hecate_rag, data_dir, DataDir),

    ok = file:write_file(filename:join(DirA, RelPath), <<"# From A\n">>),
    ok = file:write_file(filename:join(DirB, RelPath), <<"# From B\n">>),
    ok = refresh_corpus_scheduler:scan(),

    IdA = <<RepoA/binary, "/", RelPath/binary>>,
    IdB = <<RepoB/binary, "/", RelPath/binary>>,
    ?assertEqual({ok, #{source_path => IdA, raw_bytes => <<"# From A\n">>}},
                 rag_store:get_source_content(IdA)),
    ?assertEqual({ok, #{source_path => IdB, raw_bytes => <<"# From B\n">>}},
                 rag_store:get_source_content(IdB)),

    ok = application:unset_env(hecate_rag, corpus_repos_config),
    ok = application:unset_env(hecate_rag, data_dir).

%%% Internals

%% Binary-keyed, matching what `maybe_*''s `from_map/1' expects and what
%% the real HTTP layer actually sends (JSON-decoded params) — these
%% helpers exercise the same shape as a real caller, not a convenience one.
ingest(DocId, SourcePath, RawBytes) ->
    maybe_ingest_document:ingest(#{
        <<"document_id">> => DocId, <<"source_path">> => SourcePath,
        <<"source_type">> => <<"text/markdown">>, <<"raw_bytes">> => RawBytes
    }).

embed(DocId) ->
    maybe_embed_document:embed(#{<<"document_id">> => DocId}).

prune(DocId) ->
    maybe_prune_chunks:prune(#{<<"document_id">> => DocId}).

%% chunk_id is content/source_path-derived (markdown_chunker), not
%% document-id-derived, so source_path is what identifies "our" hit among
%% whatever else this store already holds.
hit_from_source(Hits, SourcePath) ->
    lists:any(fun(#{source_path := SP}) -> SP =:= SourcePath end, Hits).

fresh_id() ->
    integer_to_binary(erlang:unique_integer([positive, monotonic])).

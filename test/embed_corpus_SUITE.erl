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
         embed_without_ingest_errors/1]).

all() ->
    [ingest_embed_search_prune_round_trip, sources_query_round_trip,
     embed_without_ingest_errors].

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

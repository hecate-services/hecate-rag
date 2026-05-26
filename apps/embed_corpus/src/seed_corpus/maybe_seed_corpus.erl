%%% @doc Handler for `seed_corpus_v1`.
%%%
%%% Bulk-loads a directory of markdown into `rag_store'. Walks files,
%%% header-chunks each, embeds each chunk via `hecate_embed', persists
%%% via `rag_store:add_chunk/4'.
%%%
%%% INTENTIONALLY BYPASSES EVOQ for this dev/bulk path:
%%%
%%%   - This is a control-plane operation (rebuild from filesystem),
%%%     not the per-document audit-worthy event flow that the existing
%%%     `embed_document_v1' / `document_embedded_v1' projection
%%%     covers.
%%%
%%%   - Going through evoq would emit one event per chunk, which is
%%%     the wrong granularity for seeding (no per-aggregate stream
%%%     identity, no useful audit value, and a 5-10x storage cost
%%%     over the chunk itself).
%%%
%%% If/when we want event-sourced re-ingest semantics, add a separate
%%% command. Don't conflate the two.
-module(maybe_seed_corpus).

-export([
    seed/1,
    seed_async/1,
    dispatch/1,
    handle/1,
    handle/2
]).

-type stats() :: #{
    files       := non_neg_integer(),
    chunks      := non_neg_integer(),
    embeds      := non_neg_integer(),
    embed_errors := non_neg_integer(),
    skipped     := non_neg_integer(),
    elapsed_ms  := non_neg_integer()
}.

%%% Public entry — synchronous

-spec seed(seed_corpus_v1:t() | map()) -> {ok, stats()} | {error, term()}.
seed(Cmd) when is_tuple(Cmd) ->
    case seed_corpus_v1:validate(Cmd) of
        ok ->
            RootDir = seed_corpus_v1:get_root_dir(Cmd),
            Glob    = seed_corpus_v1:get_glob(Cmd),
            Exclude = seed_corpus_v1:get_exclude_globs(Cmd),
            do_seed(RootDir, Glob, Exclude);
        {error, _} = E -> E
    end;
seed(Params) when is_map(Params) ->
    case seed_corpus_v1:from_map(Params) of
        {ok, Cmd}      -> seed(Cmd);
        {error, _} = E -> E
    end.

%%% Public entry — async (fire-and-forget worker process)

-spec seed_async(seed_corpus_v1:t() | map()) -> {ok, #{job_pid := pid()}} | {error, term()}.
seed_async(Params) ->
    Owner = self(),
    Pid = spawn(fun() -> Owner ! {seed_done, self(), seed(Params)} end),
    {ok, #{job_pid => Pid}}.

%%% Standard handler shape (for parity with sibling slices; no event emitted)

-spec handle(seed_corpus_v1:t()) ->
    {ok, []} | {error, term()}.
handle(Cmd) -> handle(Cmd, undefined).

-spec handle(seed_corpus_v1:t(), term()) ->
    {ok, []} | {error, term()}.
handle(Cmd, _State) ->
    case seed(Cmd) of
        {ok, _Stats}    -> {ok, []};
        {error, _} = E  -> E
    end.

-spec dispatch(seed_corpus_v1:t()) -> ok | {error, term()}.
dispatch(Cmd) ->
    case seed(Cmd) of
        {ok, _Stats}   -> ok;
        {error, _} = E -> E
    end.

%%% Internals

do_seed(undefined, _Glob, _Exclude) ->
    {error, missing_root_dir};
do_seed(RootDir, Glob, Exclude) when is_binary(RootDir) ->
    do_seed(binary_to_list(RootDir), Glob, Exclude);
do_seed(RootDir, Glob, Exclude) when is_list(RootDir) ->
    case filelib:is_dir(RootDir) of
        false -> {error, {root_dir_not_found, RootDir}};
        true  -> walk_and_index(RootDir, to_str(Glob), to_strs(Exclude))
    end.

walk_and_index(RootDir, Glob, Excludes) ->
    Started = erlang:monotonic_time(millisecond),
    Files = filelib:wildcard(filename:join(RootDir, Glob)),
    Filtered = lists:filter(fun(F) -> not excluded(F, Excludes) end, Files),
    Stats0 = #{files => 0, chunks => 0, embeds => 0,
               embed_errors => 0, skipped => 0, elapsed_ms => 0},
    logger:info("[seed_corpus] starting: root=~ts files=~p (after excludes from ~p)",
                [RootDir, length(Filtered), length(Files)]),
    {ok, Model} = hecate_embed:default_model(),
    Stats = lists:foldl(
        fun(File, Acc) -> ingest_file(File, RootDir, Model, Acc) end,
        Stats0,
        Filtered
    ),
    Stats1 = Stats#{
        files      => length(Filtered),
        elapsed_ms => erlang:monotonic_time(millisecond) - Started
    },
    logger:info("[seed_corpus] done: ~p", [Stats1]),
    {ok, Stats1}.

ingest_file(AbsPath, RootDir, Model, Acc0) ->
    RelPath = list_to_binary(string:replace(AbsPath, RootDir ++ "/", "", leading)),
    case markdown_chunker:chunk_file(AbsPath, RelPath) of
        {ok, []} ->
            bump(skipped, Acc0);
        {ok, Chunks} ->
            lists:foldl(
                fun(C, Acc) -> embed_and_store(C, Model, Acc) end,
                Acc0,
                Chunks
            );
        {error, Reason} ->
            logger:warning("[seed_corpus] read error: ~ts ~p", [AbsPath, Reason]),
            bump(skipped, Acc0)
    end.

embed_and_store(Chunk, Model, Acc) ->
    #{chunk_id := Id, content := Content} = Chunk,
    Meta = maps:without([chunk_id, content], Chunk),
    case hecate_embed:embed(Model, Content) of
        {ok, Vec} ->
            case rag_store:add_chunk(Id, Content, Vec, Meta) of
                ok ->
                    bump([chunks, embeds], Acc);
                {error, Reason} ->
                    logger:warning("[seed_corpus] store error chunk=~s ~p", [Id, Reason]),
                    bump([chunks, embed_errors], Acc)
            end;
        {error, Reason} ->
            logger:warning("[seed_corpus] embed error chunk=~s ~p", [Id, Reason]),
            bump([chunks, embed_errors], Acc)
    end.

excluded(_File, []) -> false;
excluded(File, Globs) ->
    lists:any(fun(G) -> match_glob(File, G) end, Globs).

%% Match a glob loosely: substring OR filename:match-like semantics
%% (filelib:wildcard returns absolute paths; we accept naive substring globs).
match_glob(File, Glob) ->
    %% Naive: substring match on the path. Covers `_build`, `priv`, `assets/`.
    string:find(File, Glob) =/= nomatch.

bump(Key, Acc) when is_atom(Key) ->
    maps:update_with(Key, fun(V) -> V + 1 end, Acc);
bump(Keys, Acc) when is_list(Keys) ->
    lists:foldl(fun bump/2, Acc, Keys).

to_str(undefined)              -> "**/*.md";
to_str(B) when is_binary(B)    -> binary_to_list(B);
to_str(L) when is_list(L)      -> L.

to_strs(undefined)             -> [];
to_strs(L) when is_list(L)     ->
    [case X of B when is_binary(B) -> binary_to_list(B); S -> S end || X <- L].

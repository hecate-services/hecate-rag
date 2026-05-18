%%% @doc rag_store — the shared retrieval state.
%%%
%%% Holds two handles for the whole service:
%%%
%%%   - the in-BEAM ANN index (`hecate_vector`), opened under the
%%%     name `rag_chunks' with dim = the default embed dim
%%%   - the SQLite read model (`esqlite3`), with a single `chunks'
%%%     table for chunk content + metadata
%%%
%%% Two write paths:
%%%
%%%   - `add_chunk/4' from the projection in `project_chunks'
%%%     (called on document_embedded_v1)
%%%   - `forget_chunk/1' from `chunks_pruned_v1' projection
%%%
%%% Two read paths:
%%%
%%%   - `search/2' from `search_chunks_semantic' (semantic search
%%%     entry, returns enriched hits)
%%%   - `get/1' from `get_chunk_by_id'
%%%
%%% Lazy boot: the gen_server starts cold; the first request opens
%%% the index + sqlite db. Lets the service stay up even when
%%% paths aren't yet writable (e.g. test harness, early boot).
-module(rag_store).
-behaviour(gen_server).

-export([
    start_link/0,
    add_chunk/4,
    forget_chunk/1,
    search/2,
    get/1,
    size/0
]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(INDEX_NAME, rag_chunks).
-define(DEFAULT_DIM, 384).

-record(state, {
    index  = undefined :: pid() | atom() | undefined,
    db     = undefined :: term() | undefined,
    dim    = ?DEFAULT_DIM :: pos_integer()
}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec add_chunk(binary(), binary(), [float()], map()) -> ok | {error, term()}.
add_chunk(ChunkId, Content, Vector, Meta)
  when is_binary(ChunkId), is_binary(Content), is_list(Vector), is_map(Meta) ->
    gen_server:call(?MODULE, {add_chunk, ChunkId, Content, Vector, Meta}).

-spec forget_chunk(binary()) -> ok.
forget_chunk(ChunkId) when is_binary(ChunkId) ->
    gen_server:call(?MODULE, {forget_chunk, ChunkId}).

-spec search([float()], pos_integer()) ->
    {ok, [#{chunk_id := binary(), content := binary(), score := float(), source_path => binary()}]}
    | {error, term()}.
search(Vector, TopK) when is_list(Vector), is_integer(TopK), TopK > 0 ->
    gen_server:call(?MODULE, {search, Vector, TopK}).

-spec get(binary()) -> {ok, map()} | {error, not_found}.
get(ChunkId) when is_binary(ChunkId) ->
    gen_server:call(?MODULE, {get, ChunkId}).

-spec size() -> non_neg_integer().
size() ->
    gen_server:call(?MODULE, size).

%%% gen_server

init([]) ->
    {ok, #state{dim = configured_dim()}}.

handle_call({add_chunk, Id, Content, Vec, Meta}, _From, S0) ->
    case ensure_open(S0) of
        {ok, #state{index = Idx, db = Db} = S} ->
            ok = hecate_vector:add(Idx, Id, Vec),
            ok = upsert_chunk(Db, Id, Content, Meta),
            {reply, ok, S};
        {error, _} = E ->
            {reply, E, S0}
    end;

handle_call({forget_chunk, Id}, _From, S0) ->
    case ensure_open(S0) of
        {ok, #state{db = Db} = S} ->
            ok = delete_chunk(Db, Id),
            %% NOTE: hecate_vector doesn't expose a delete primitive yet
            %% (USearch has one; the brute-force stub doesn't). For now
            %% the vector lingers and the SQL row is gone — search will
            %% return a hit with no content and the desk filters it.
            {reply, ok, S};
        {error, _} = E ->
            {reply, E, S0}
    end;

handle_call({search, Vec, TopK}, _From, S0) ->
    case ensure_open(S0) of
        {ok, #state{index = Idx, db = Db} = S} ->
            case hecate_vector:search(Idx, Vec, TopK) of
                {ok, RawHits} ->
                    Enriched = lists:filtermap(
                        fun({Id, Score}) -> enrich(Db, Id, Score) end,
                        RawHits
                    ),
                    {reply, {ok, Enriched}, S};
                {error, _} = E ->
                    {reply, E, S}
            end;
        {error, _} = E ->
            {reply, E, S0}
    end;

handle_call({get, Id}, _From, S0) ->
    case ensure_open(S0) of
        {ok, #state{db = Db} = S} ->
            {reply, get_chunk(Db, Id), S};
        {error, _} = E ->
            {reply, E, S0}
    end;

handle_call(size, _From, S0) ->
    case ensure_open(S0) of
        {ok, #state{index = Idx} = S} -> {reply, hecate_vector:size(Idx), S};
        {error, _}                    -> {reply, 0, S0}
    end;

handle_call(_, _From, S) -> {reply, {error, unknown_call}, S}.

handle_cast(_, S) -> {noreply, S}.
handle_info(_, S) -> {noreply, S}.
terminate(_, _)   -> ok.

%%% Internals

configured_dim() ->
    application:get_env(hecate_embed, default_dim, ?DEFAULT_DIM).

ensure_open(#state{index = Idx, db = Db} = S) when Idx =/= undefined, Db =/= undefined ->
    {ok, S};
ensure_open(#state{dim = Dim} = S) ->
    case open_index(Dim) of
        {ok, Idx} ->
            case open_db() of
                {ok, Db} -> {ok, S#state{index = Idx, db = Db}};
                {error, _} = E -> E
            end;
        {error, _} = E -> E
    end.

open_index(Dim) ->
    try
        hecate_vector:open(?INDEX_NAME, #{dim => Dim, capacity => 100_000})
    catch C:R -> {error, {vector_open, C, R}}
    end.

open_db() ->
    DbPath = filename:join(data_dir(), "chunks.sqlite"),
    ok = filelib:ensure_dir(DbPath),
    case esqlite3:open(DbPath) of
        {ok, Db} ->
            ok = run_migration(Db),
            {ok, Db};
        {error, _} = E -> E
    end.

data_dir() ->
    application:get_env(hecate_rag, data_dir, "priv/data").

run_migration(Db) ->
    Sql =
        "CREATE TABLE IF NOT EXISTS chunks ("
        "  chunk_id     TEXT PRIMARY KEY,"
        "  content      TEXT NOT NULL,"
        "  source_path  TEXT,"
        "  meta         TEXT,"  %% JSON-encoded
        "  added_at_ms  INTEGER NOT NULL"
        ");",
    esqlite3:exec(Sql, Db).

upsert_chunk(Db, Id, Content, Meta) ->
    SourcePath = maps:get(source_path, Meta, <<>>),
    MetaJson   = jsx:encode(Meta),
    NowMs      = erlang:system_time(millisecond),
    Sql =
        "INSERT INTO chunks (chunk_id, content, source_path, meta, added_at_ms) "
        "VALUES (?1, ?2, ?3, ?4, ?5) "
        "ON CONFLICT(chunk_id) DO UPDATE SET "
        "  content     = excluded.content,"
        "  source_path = excluded.source_path,"
        "  meta        = excluded.meta,"
        "  added_at_ms = excluded.added_at_ms;",
    case esqlite3:q(Sql, [Id, Content, SourcePath, MetaJson, NowMs], Db) of
        {error, _} = E -> E;
        _              -> ok
    end.

delete_chunk(Db, Id) ->
    case esqlite3:q("DELETE FROM chunks WHERE chunk_id = ?1", [Id], Db) of
        {error, _} = E -> E;
        _              -> ok
    end.

enrich(Db, Id, Score) ->
    case get_chunk(Db, Id) of
        {ok, Row} -> {true, Row#{score => Score}};
        _         -> false   %% chunk was pruned but vector lingered
    end.

get_chunk(Db, Id) ->
    Sql = "SELECT chunk_id, content, source_path, meta FROM chunks WHERE chunk_id = ?1",
    case esqlite3:q(Sql, [Id], Db) of
        [{IdB, Content, SourcePath, MetaJson}] ->
            Meta = try jsx:decode(MetaJson, [return_maps]) catch _:_ -> #{} end,
            {ok, #{
                chunk_id    => IdB,
                content     => Content,
                source_path => SourcePath,
                meta        => Meta
            }};
        _ ->
            {error, not_found}
    end.

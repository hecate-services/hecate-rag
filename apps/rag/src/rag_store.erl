%%% @doc rag_store — the shared retrieval state.
%%%
%%% One `barrel' record-mode database (`barrel_docdb' + `barrel_vectordb'
%%% composed behind one handle, see beam-campus/barrel): a chunk's content,
%%% metadata and vector all live under its `chunk_id', kept in sync
%%% automatically by barrel's embedding policy — `put_chunk/3' never
%%% computes or passes a vector itself. Source records (one per ingested
%%% document) share the same database as a second, unembedded document
%%% shape, distinguished by a `type' field and an id prefix so a
%%% `document_id' can never collide with a `chunk_id' in the same id space.
%%%
%%% Replaces the former esqlite (chunks/sources SQL tables) + hecate_vector
%%% (brute-force ANN scaffold, no working persistence) + hecate_embed
%%% (separate embed-then-store calls) combination: one dependency instead
%%% of three, and no hand-paired "SQL row here, vector there" bookkeeping
%%% for delete to get wrong.
%%%
%%% Write paths:
%%%
%%%   - `put_chunk/3' — called directly by `ingest_document'/`embed_document'
%%%     and by `seed_corpus'. No event sourcing: chunks/vectors are a
%%%     deterministic function of (source text, chunker, embedding model),
%%%     not a business fact anyone decided, so there is nothing here worth
%%%     replaying from history.
%%%   - `forget_chunk/1' — called directly by `prune_chunks'.
%%%   - `upsert_source/1' — called directly by `ingest_document'.
%%%
%%% Read paths:
%%%
%%%   - `search_text/2' — semantic search from a query string; barrel
%%%     embeds the query itself.
%%%   - `search_vector/2' — semantic search from an already-computed vector.
%%%   - `get/1' — `get_chunk_by_id'.
%%%   - `list_chunks_by_source/2' — `list_chunks_by_source'.
%%%   - `get_source/1' — `get_source_by_id'.
%%%   - `list_sources/2' — `list_sources_page'.
%%%
%%% Lazy boot: the gen_server starts cold; the first request opens the
%%% database. Lets the service stay up even when paths aren't yet writable
%%% (e.g. test harness, early boot).
-module(rag_store).
-behaviour(gen_server).

-export([
    start_link/0,
    put_chunk/3,
    forget_chunk/1,
    search_text/2,
    search_vector/2,
    get/1,
    size/0,
    upsert_source/1,
    get_source/1,
    get_source_content/1,
    list_sources/2,
    list_chunks_by_source/2
]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(DB_NAME, rag_chunks).
-define(DEFAULT_DIM, 768).
-define(SOURCE_ID_PREFIX, "source:").

-record(state, {db = undefined :: map() | undefined}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Insert or replace a chunk. `Meta' carries whatever
%% `markdown_chunker' attached (source_path, header_path, kind, start_line,
%% end_line) plus anything else the caller wants searchable in hit
%% metadata — barrel embeds `content' per the configured policy, no vector
%% is computed or passed here.
-spec put_chunk(binary(), binary(), map()) -> ok | {error, term()}.
put_chunk(ChunkId, Content, Meta)
  when is_binary(ChunkId), is_binary(Content), is_map(Meta) ->
    gen_server:call(?MODULE, {put_chunk, ChunkId, Content, Meta}).

-spec forget_chunk(binary()) -> ok | {error, term()}.
forget_chunk(ChunkId) when is_binary(ChunkId) ->
    gen_server:call(?MODULE, {forget_chunk, ChunkId}).

-spec search_text(binary(), pos_integer()) -> {ok, [map()]} | {error, term()}.
search_text(QueryText, TopK)
  when is_binary(QueryText), is_integer(TopK), TopK > 0 ->
    gen_server:call(?MODULE, {search_text, QueryText, TopK}).

-spec search_vector([float()], pos_integer()) -> {ok, [map()]} | {error, term()}.
search_vector(Vector, TopK)
  when is_list(Vector), is_integer(TopK), TopK > 0 ->
    gen_server:call(?MODULE, {search_vector, Vector, TopK}).

-spec get(binary()) -> {ok, map()} | {error, not_found}.
get(ChunkId) when is_binary(ChunkId) ->
    gen_server:call(?MODULE, {get, ChunkId}).

-spec size() -> non_neg_integer().
size() ->
    gen_server:call(?MODULE, size).

%% @doc Record (or update) that a document has been ingested. Map keys:
%% `document_id' (required), `source_path', `source_type', `raw_bytes'
%% (all optional). `raw_bytes' is what `embed_document' later reads back
%% to chunk — with no event-sourced aggregate, the source record IS where
%% ingested content lives between the two calls.
-spec upsert_source(map()) -> ok | {error, term()}.
upsert_source(#{document_id := Id} = Source) when is_binary(Id) ->
    gen_server:call(?MODULE, {upsert_source, Source}).

%% @doc The public source row: id/path/type, no `raw_bytes' (kept out of
%% the default shape the same way `chunk_meta/1' hides `_embedding' —
%% derived/bulky fields are opt-in, not default).
-spec get_source(binary()) -> {ok, map()} | {error, not_found}.
get_source(DocumentId) when is_binary(DocumentId) ->
    gen_server:call(?MODULE, {get_source, DocumentId}).

%% @doc Internal use (`embed_document'): the source's `source_path' and
%% `raw_bytes', to chunk. Not part of the public query surface.
-spec get_source_content(binary()) -> {ok, map()} | {error, not_found}.
get_source_content(DocumentId) when is_binary(DocumentId) ->
    gen_server:call(?MODULE, {get_source_content, DocumentId}).

-spec list_sources(non_neg_integer(), pos_integer()) -> {ok, [map()]}.
list_sources(Offset, Limit)
  when is_integer(Offset), Offset >= 0, is_integer(Limit), Limit > 0 ->
    gen_server:call(?MODULE, {list_sources, Offset, Limit}).

-spec list_chunks_by_source(binary(), pos_integer()) -> {ok, [map()]}.
list_chunks_by_source(SourcePath, Limit)
  when is_binary(SourcePath), is_integer(Limit), Limit > 0 ->
    gen_server:call(?MODULE, {list_chunks_by_source, SourcePath, Limit}).

%%% gen_server

init([]) ->
    {ok, #state{}}.

handle_call({put_chunk, Id, Content, Meta}, _From, S0) ->
    with_db(S0, fun(Db) -> put_chunk_doc(Db, Id, Content, Meta) end);

handle_call({forget_chunk, Id}, _From, S0) ->
    with_db(S0, fun(Db) -> normalize_write(barrel:delete_doc(Db, Id)) end);

handle_call({search_text, QueryText, TopK}, _From, S0) ->
    with_db(S0, fun(Db) -> to_hits(barrel:search(Db, QueryText, #{k => TopK})) end);

handle_call({search_vector, Vector, TopK}, _From, S0) ->
    with_db(S0, fun(Db) -> to_hits(barrel:search_vector(Db, Vector, #{k => TopK})) end);

handle_call({get, Id}, _From, S0) ->
    with_db(S0, fun(Db) -> chunk_from_doc(barrel:get_doc(Db, Id)) end);

handle_call(size, _From, S0) ->
    with_db(S0, fun(Db) -> chunk_count(Db) end, 0);

handle_call({upsert_source, Source}, _From, S0) ->
    with_db(S0, fun(Db) -> put_source_doc(Db, Source) end);

handle_call({get_source, Id}, _From, S0) ->
    with_db(S0, fun(Db) -> source_from_doc(barrel:get_doc(Db, source_id(Id))) end);

handle_call({get_source_content, Id}, _From, S0) ->
    with_db(S0, fun(Db) -> source_content_from_doc(barrel:get_doc(Db, source_id(Id))) end);

handle_call({list_sources, Offset, Limit}, _From, S0) ->
    with_db(S0, fun(Db) -> list_sources_page(Db, Offset, Limit) end, {ok, []});

handle_call({list_chunks_by_source, SourcePath, Limit}, _From, S0) ->
    with_db(S0, fun(Db) -> list_chunks_by_source_page(Db, SourcePath, Limit) end, {ok, []});

handle_call(_, _From, S) -> {reply, {error, unknown_call}, S}.

handle_cast(_, S) -> {noreply, S}.
handle_info(_, S) -> {noreply, S}.
terminate(_, _)   -> ok.

%%% Internals — lazy open
%%
%% `Fun' returns a plain result (`ok', `{ok, _}' or `{error, _}'), never a
%% gen_server reply tuple — this is the one place that wraps it, so every
%% `handle_call' clause above reads as "what does this call actually
%% compute" with no `{reply, _, State}' boilerplate repeated per clause.
%% `size/0' and the list queries pass a 3rd-arg fallback because their
%% "no db yet" answer is a value (`0', `{ok, []}'), not an error.

with_db(S0, Fun) ->
    with_db(S0, Fun, undefined).

with_db(#state{db = undefined} = S0, Fun, OnOpenError) ->
    case open_db() of
        {ok, Db}        -> reply_result(Fun(Db), S0#state{db = Db});
        {error, _} = E  -> {reply, on_open_error(OnOpenError, E), S0}
    end;
with_db(#state{db = Db} = S0, Fun, _OnOpenError) ->
    reply_result(Fun(Db), S0).

on_open_error(undefined, Error) -> Error;
on_open_error(Fallback, _Error) -> Fallback.

reply_result(Result, State) -> {reply, Result, State}.

open_db() ->
    barrel:open(?DB_NAME, #{
        docdb => #{data_dir => data_dir()},
        embedding => #{
            fields => [<<"content">>],
            mode => sync,
            embedder => embedder(),
            dimensions => configured_dim(),
            metadata_fields => [<<"source_path">>, <<"header_path">>, <<"kind">>,
                                <<"start_line">>, <<"end_line">>, <<"type">>]
        }
    }).

data_dir() ->
    application:get_env(hecate_rag, data_dir, "/var/lib/hecate-rag/data").

configured_dim() ->
    application:get_env(hecate_rag, embed_dim, ?DEFAULT_DIM).

embedder() ->
    Url = application:get_env(hecate_rag, embed_url, <<"http://127.0.0.1:11434">>),
    Model = application:get_env(hecate_rag, embed_model, <<"nomic-embed-text">>),
    {ollama, #{url => to_bin(Url), model => to_bin(Model)}}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L)   -> list_to_binary(L).

%%% Internals — chunks

%% `Meta' may arrive shaped like a `markdown_chunker' chunk (atom keys,
%% an atom `kind' of `prose'/`code') — that is this store's one caller-
%% facing convenience, not something every caller should have to
%% pre-normalize. barrel documents are JSON-shaped: everything becomes a
%% binary key, and the one known atom-valued field (`kind') becomes a
%% binary value too, or the doc would end up with both an atom and a
%% binary variant of the same field.
put_chunk_doc(Db, Id, Content, Meta) ->
    Shaped = json_shape(Meta),
    Doc = Shaped#{<<"id">> => Id, <<"content">> => Content},
    normalize_write(barrel:put_doc(Db, Doc)).

json_shape(Map) ->
    maps:fold(fun(K, V, Acc) -> Acc#{json_key(K) => json_value(V)} end, #{}, Map).

json_key(K) when is_atom(K)   -> atom_to_binary(K, utf8);
json_key(K) when is_binary(K) -> K.

json_value(V) when is_atom(V), V =/= true, V =/= false, V =/= undefined ->
    atom_to_binary(V, utf8);
json_value(V) -> V.

normalize_write({ok, _RevInfo}) -> ok;
normalize_write({error, _} = E) -> E.

chunk_from_doc({ok, #{<<"id">> := Id, <<"content">> := Content} = Doc}) ->
    {ok, #{chunk_id => Id, content => Content, meta => chunk_meta(Doc)}};
chunk_from_doc(_NotFound) ->
    {error, not_found}.

chunk_meta(Doc) ->
    maps:without([<<"id">>, <<"content">>, <<"_embedding">>, <<"_rev">>, <<"type">>], Doc).

chunk_count(Db) ->
    case barrel:vector_stats(Db) of
        {ok, #{count := N}} -> N;
        _                   -> 0
    end.

to_hits({ok, RawHits}) ->
    {ok, [hit(H) || H <- RawHits]};
to_hits({error, _} = E) ->
    E.

hit(#{key := Id, score := Score, text := Text, metadata := Meta}) ->
    #{chunk_id => Id, content => Text, score => Score,
      source_path => maps:get(<<"source_path">>, Meta, <<>>),
      meta => maps:without([<<"source_path">>], Meta)}.

%%% Internals — sources

source_id(DocumentId) -> <<?SOURCE_ID_PREFIX, DocumentId/binary>>.

put_source_doc(Db, #{document_id := Id} = Source) ->
    Doc = #{
        <<"id">>          => source_id(Id),
        <<"type">>        => <<"source">>,
        <<"document_id">> => Id,
        <<"source_path">> => maps:get(source_path, Source, <<>>),
        <<"source_type">> => maps:get(source_type, Source, <<>>),
        <<"raw_bytes">>   => maps:get(raw_bytes, Source, <<>>)
    },
    normalize_write(barrel:put_doc(Db, Doc)).

source_from_doc({ok, #{<<"type">> := <<"source">>} = Doc}) ->
    {ok, source_row(Doc)};
source_from_doc(_NotFoundOrNotASource) ->
    {error, not_found}.

source_row(Doc) ->
    #{document_id => maps:get(<<"document_id">>, Doc),
      source_path => maps:get(<<"source_path">>, Doc, <<>>),
      source_type => maps:get(<<"source_type">>, Doc, <<>>)}.

source_content_from_doc({ok, #{<<"type">> := <<"source">>} = Doc}) ->
    {ok, #{source_path => maps:get(<<"source_path">>, Doc, <<>>),
           raw_bytes   => maps:get(<<"raw_bytes">>, Doc, <<>>)}};
source_content_from_doc(_NotFoundOrNotASource) ->
    {error, not_found}.

%% `barrel:find/3' results are not flat documents: each entry is
%% `#{<<"id">> => Id, <<"doc">> => ActualDoc}' (plus whatever else the
%% query's projection carries) — unwrap before treating it as a document.
find_doc(#{<<"doc">> := Doc}) -> Doc;
find_doc(Doc)                 -> Doc.

list_sources_page(Db, Offset, Limit) ->
    Query = #{where => [{path, [<<"type">>], <<"source">>}]},
    case barrel:find(Db, Query, #{limit => Limit, offset => Offset}) of
        {ok, Docs, _Meta} -> {ok, [source_row(find_doc(D)) || D <- Docs]};
        {error, _} = E    -> E
    end.

list_chunks_by_source_page(Db, SourcePath, Limit) ->
    Query = #{where => [{path, [<<"source_path">>], SourcePath}]},
    case barrel:find(Db, Query, #{limit => Limit}) of
        {ok, Docs, _Meta} ->
            {ok, [C || D <- Docs, {ok, C} <- [chunk_from_doc({ok, find_doc(D)})]]};
        {error, _} = E ->
            E
    end.

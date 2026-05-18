%%% @doc Projection: `document_embedded_v1' → `chunks' read model.
%%%
%%% Subscribes to `document_embedded_v1' via pg, persists every
%%% chunk in the event into `rag_store' (which owns the vector
%%% index + SQLite db). After this projection runs, the chunk is
%%% reachable via `search_chunks_semantic' and `get_chunk_by_id'.
%%%
%%% Event payload shape (per the slice's `document_embedded_v1`):
%%%   #{document_id, source_path, model_id, dim, chunks => [Chunk]}
%%% where each Chunk is
%%%   #{chunk_id, content, vector :: [float()], headings, …}
-module(document_embedded_v1_to_chunks).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(PG_SCOPE, rag).
-define(EVENT_TOPIC, <<"document_embedded_v1">>).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    pg:join(?PG_SCOPE, ?EVENT_TOPIC, self()),
    {ok, #{}}.

handle_call(_Msg, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State)         -> {noreply, State}.

handle_info({evoq_event, Envelope}, State) ->
    project(Envelope),
    {noreply, State};
handle_info(_Other, State) ->
    {noreply, State}.

terminate(_, _) -> ok.

%%% Internals

project(Envelope) ->
    Data       = data_from(Envelope),
    Chunks     = maps:get(chunks,      Data, []),
    SourcePath = maps:get(source_path, Data, <<>>),
    lists:foreach(
        fun(Chunk) -> upsert_one(Chunk, SourcePath) end,
        Chunks
    ).

%% Envelope shape from evoq is #evoq_event{data = ...} OR a bare
%% map (depending on subscription path). Handle both.
data_from(#{data := D}) -> D;
data_from(D) when is_map(D) -> D;
data_from(_) -> #{}.

upsert_one(#{chunk_id := Id, content := Content, vector := Vec} = Chunk, SourcePath) ->
    Meta = maps:without([chunk_id, content, vector], Chunk),
    Meta1 = case SourcePath of
        <<>> -> Meta;
        _    -> Meta#{source_path => SourcePath}
    end,
    rag_store:add_chunk(Id, Content, Vec, Meta1);
upsert_one(_, _) ->
    %% Malformed chunk; skip silently. A future TODO could log + count.
    ok.

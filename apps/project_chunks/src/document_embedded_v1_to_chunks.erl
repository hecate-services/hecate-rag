%%% @doc Projection: document_embedded_v1 → chunks read model.
%%%
%%% Subscribes to document_embedded_v1 via pg, writes to the SQLite `chunks` table.
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
    %% TODO: read event payload from Envelope, upsert into `chunks` table.
    %% Use esqlite via app_ragd_paths:sqlite_db/0.
    _ = Envelope,
    {noreply, State};
handle_info(_Other, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.

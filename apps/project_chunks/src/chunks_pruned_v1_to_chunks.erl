%%% @doc Projection: `chunks_pruned_v1' → `chunks' read model.
%%%
%%% Deletes the listed chunk ids from `rag_store'. The vector index
%%% lingers (no delete primitive in hecate_vector yet); only the
%%% SQL row goes away. Searches that hit the orphan vector get a
%%% null content and are filtered by `rag_store:enrich/3'.
-module(chunks_pruned_v1_to_chunks).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(PG_SCOPE, rag).
-define(EVENT_TOPIC, <<"chunks_pruned_v1">>).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    pg:join(?PG_SCOPE, ?EVENT_TOPIC, self()),
    {ok, #{}}.

handle_call(_, _, S) -> {reply, ok, S}.
handle_cast(_, S)    -> {noreply, S}.

handle_info({evoq_event, Envelope}, S) ->
    project(Envelope),
    {noreply, S};
handle_info(_, S) ->
    {noreply, S}.

terminate(_, _) -> ok.

%%% Internals

project(#{data := D}) -> project_data(D);
project(D) when is_map(D) -> project_data(D);
project(_) -> ok.

project_data(#{chunk_ids := Ids}) when is_list(Ids) ->
    lists:foreach(fun(Id) -> safe_forget(Id) end, Ids);
project_data(_) ->
    ok.

safe_forget(Id) when is_binary(Id) ->
    rag_store:forget_chunk(Id);
safe_forget(_) ->
    ok.

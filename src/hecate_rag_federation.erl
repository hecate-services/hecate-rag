%%% @doc Federation wiring for hecate-rag.
%%%
%%% Two jobs at boot:
%%%
%%%   1. Once hecate_om has its (Pool, Realm), call
%%%      `macula_rag:configure(Pool, Realm)' so the federation lib
%%%      can publish summaries + advertise its RPC method +
%%%      subscribe to peer summaries.
%%%
%%%   2. Register a responder callback that delegates incoming
%%%      `macula-rag.query' calls into hecate-rag's
%%%      `serve_retrieval` slice via `answer_query_v1` /
%%%      `maybe_answer_query`.
%%%
%%% Retries every `retry_ms' until hecate_om is configured. Both
%%% steps are idempotent — re-running them is harmless if a
%%% reconfigure happens.
-module(hecate_rag_federation).
-behaviour(gen_server).

-export([start_link/0, status/0, kick/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(SHARD_ID,   <<"hecate-rag">>).
-define(RETRY_MS,   2_000).

-record(state, {
    configured = false :: boolean(),
    responder  = false :: boolean()
}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

status() ->
    gen_server:call(?MODULE, status).

%% @doc Kick the worker to retry now (e.g. after hecate_om reconnects).
kick() ->
    gen_server:cast(?MODULE, kick).

%%% gen_server

init([]) ->
    self() ! try_bind,
    {ok, #state{}}.

handle_call(status, _From, S) ->
    {reply, #{configured => S#state.configured,
              responder  => S#state.responder}, S};
handle_call(_, _From, S) ->
    {reply, {error, unknown_call}, S}.

handle_cast(kick, S) ->
    self() ! try_bind,
    {noreply, S};
handle_cast(_, S) ->
    {noreply, S}.

handle_info(try_bind, S) ->
    S1 = maybe_configure(S),
    S2 = maybe_register_responder(S1),
    schedule_retry_if_incomplete(S2),
    {noreply, S2};
handle_info(_, S) ->
    {noreply, S}.

terminate(_, _) -> ok.

%%% Internals

maybe_configure(#state{configured = true} = S) -> S;
maybe_configure(S) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            case safe_configure(Pool, Realm) of
                ok ->
                    logger:info("[hecate_rag_federation] macula_rag configured"),
                    S#state{configured = true};
                {error, Reason} ->
                    logger:warning("[hecate_rag_federation] configure failed: ~p", [Reason]),
                    S
            end;
        _ ->
            S
    end.

maybe_register_responder(#state{configured = false} = S) -> S;
maybe_register_responder(#state{responder  = true}  = S) -> S;
maybe_register_responder(S) ->
    Fun = fun answer_query/2,
    case safe_register(?SHARD_ID, Fun) of
        ok ->
            logger:info("[hecate_rag_federation] responder registered for ~s", [?SHARD_ID]),
            S#state{responder = true};
        {error, Reason} ->
            logger:warning("[hecate_rag_federation] register_responder failed: ~p", [Reason]),
            S
    end.

schedule_retry_if_incomplete(#state{configured = true, responder = true}) ->
    ok;
schedule_retry_if_incomplete(_) ->
    erlang:send_after(?RETRY_MS, self(), try_bind),
    ok.

safe_configure(Pool, Realm) ->
    try
        ok = macula_rag:configure(Pool, Realm),
        ok
    catch C:R -> {error, {C, R}}
    end.

safe_register(ShardId, Fun) ->
    try
        ok = macula_rag:register_responder(ShardId, Fun),
        ok
    catch C:R -> {error, {C, R}}
    end.

%% @doc Responder callback. macula_rag passes us the inbound
%% query map + opts; we shape it into an `answer_query_v1' command
%% and dispatch via the slice handler. Returns `{ok, Hits}` or
%% `{error, Reason}'.
%%
%% The `query` term is opaque per macula-rag's contract. For
%% hecate-rag we expect at least #{<<"query_text">> => binary()}.
-spec answer_query(map(), map()) -> {ok, [map()]} | {error, term()}.
answer_query(Query, Opts) when is_map(Query), is_map(Opts) ->
    TopK = maps:get(top_k, Opts, 10),
    %% Federation contract: macula_rag passes the inbound query map
    %% straight from the caller. We forward it to the search desk,
    %% which embeds the query text + walks the vector index +
    %% enriches hits with content. No event store dispatch on the
    %% federation path — those are read-only queries.
    Params = Query#{<<"top_k">> => TopK},
    maybe_answer_query:retrieve(Params);
answer_query(_, _) ->
    {error, bad_query}.

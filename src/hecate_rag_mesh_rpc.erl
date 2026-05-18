%%% @doc Registers Macula RPC handlers for the capabilities
%%% advertised by `hecate_rag_service:capabilities/0`.
%%%
%%% Production traffic to hecate-rag flows over the mesh. A plugin
%%% on a user laptop calls:
%%%
%%%   macula:call(LocalPool, Realm,
%%%               <<"hecate-rag.answer_query">>, Params, Timeout).
%%%
%%% The local macula-station routes the RPC to the infrastructure
%%% node running hecate-rag. The SDK invokes the handler registered
%%% via `macula:advertise/5` — `{?MODULE, handle_rpc_<method>}` here
%%% — which dispatches into the matching slice handler.
%%%
%%% The handler form `{module(), atom()}` keeps the dispatch table
%%% small. We register one entry per capability so the procedure
%%% string is encoded once at advertise time, not per-call.
%%%
%%% Degrades gracefully: if `hecate_om:macula_client/0` returns
%%% `{error, no_client}` (no station seeds configured / station not
%%% up yet) the gen_server still starts and `dispatch/2` keeps
%%% working for tests and the local HTTP admin path.
-module(hecate_rag_mesh_rpc).
-behaviour(gen_server).

-export([
    start_link/0,
    dispatch/2,
    %% Handlers — invoked by the SDK on inbound RPC. One per capability.
    handle_ingest_document/1,
    handle_embed_document/1,
    handle_prune_chunks/1,
    handle_answer_query/1,
    handle_rerank_results/1,
    handle_get_chunk_by_id/1,
    handle_search_chunks_semantic/1,
    handle_list_chunks_by_source/1,
    handle_get_source_by_id/1,
    handle_list_sources_page/1
]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Test/debug entry point that bypasses the SDK and dispatches
%% directly to the matching slice handler.
-spec dispatch(binary(), map()) -> {ok, term()} | {error, term()}.
dispatch(Method, Params) when is_binary(Method), is_map(Params) ->
    gen_server:call(?MODULE, {dispatch, Method, Params}).

%%% gen_server

init([]) ->
    %% Try to advertise every capability against the SDK. If we
    %% don't have a client yet, skip — capabilities() is still
    %% reachable via hecate_om and the local HTTP API.
    advertise_all(),
    {ok, #{}}.

handle_call({dispatch, Method, Params}, _From, S) ->
    {reply, route(Method, Params), S};
handle_call(_Msg, _From, S) ->
    {reply, {error, unknown_call}, S}.

handle_cast(_Msg, S) -> {noreply, S}.
handle_info(_Msg, S) -> {noreply, S}.
terminate(_Reason, _State) -> ok.

%%% Internal: register every capability with the SDK

advertise_all() ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            lists:foreach(
                fun({CapName, Handler}) ->
                    try
                        ok = macula:advertise(Pool, Realm, CapName,
                                              {?MODULE, Handler}, #{})
                    catch _:_ -> ok
                    end
                end,
                handler_table()
            );
        _ ->
            ok
    end.

handler_table() ->
    [
        {<<"hecate-rag.ingest_document">>,        handle_ingest_document},
        {<<"hecate-rag.embed_document">>,         handle_embed_document},
        {<<"hecate-rag.prune_chunks">>,           handle_prune_chunks},
        {<<"hecate-rag.answer_query">>,           handle_answer_query},
        {<<"hecate-rag.rerank_results">>,         handle_rerank_results},
        {<<"hecate-rag.get_chunk_by_id">>,        handle_get_chunk_by_id},
        {<<"hecate-rag.search_chunks_semantic">>, handle_search_chunks_semantic},
        {<<"hecate-rag.list_chunks_by_source">>,  handle_list_chunks_by_source},
        {<<"hecate-rag.get_source_by_id">>,       handle_get_source_by_id},
        {<<"hecate-rag.list_sources_page">>,      handle_list_sources_page}
    ].

%%% Internal: SDK handler entry points (one per capability)

handle_ingest_document(P)        -> route(<<"hecate-rag.ingest_document">>, P).
handle_embed_document(P)         -> route(<<"hecate-rag.embed_document">>, P).
handle_prune_chunks(P)           -> route(<<"hecate-rag.prune_chunks">>, P).
handle_answer_query(P)           -> route(<<"hecate-rag.answer_query">>, P).
handle_rerank_results(P)         -> route(<<"hecate-rag.rerank_results">>, P).
handle_get_chunk_by_id(P)        -> route(<<"hecate-rag.get_chunk_by_id">>, P).
handle_search_chunks_semantic(P) -> route(<<"hecate-rag.search_chunks_semantic">>, P).
handle_list_chunks_by_source(P)  -> route(<<"hecate-rag.list_chunks_by_source">>, P).
handle_get_source_by_id(P)       -> route(<<"hecate-rag.get_source_by_id">>, P).
handle_list_sources_page(P)      -> route(<<"hecate-rag.list_sources_page">>, P).

%%% Internal: method → slice handler

route(<<"hecate-rag.ingest_document">>, P) ->
    delegate(ingest_document_v1, maybe_ingest_document, P);
route(<<"hecate-rag.embed_document">>, P) ->
    delegate(embed_document_v1, maybe_embed_document, P);
route(<<"hecate-rag.prune_chunks">>, P) ->
    delegate(prune_chunks_v1, maybe_prune_chunks, P);
route(<<"hecate-rag.answer_query">>, P) ->
    delegate(answer_query_v1, maybe_answer_query, P);
route(<<"hecate-rag.rerank_results">>, P) ->
    delegate(rerank_results_v1, maybe_rerank_results, P);
route(<<"hecate-rag.get_chunk_by_id">>, #{<<"chunk_id">> := Id}) ->
    get_chunk_by_id:handle(Id);
route(<<"hecate-rag.search_chunks_semantic">>, P) ->
    search_chunks_semantic:handle(P);
route(<<"hecate-rag.list_chunks_by_source">>, P) ->
    list_chunks_by_source:handle(P);
route(<<"hecate-rag.get_source_by_id">>, #{<<"source_id">> := Id}) ->
    get_source_by_id:handle(Id);
route(<<"hecate-rag.list_sources_page">>, P) ->
    list_sources_page:handle(P);
route(Other, _P) ->
    {error, {unknown_method, Other}}.

delegate(CmdMod, HandlerMod, Params) ->
    case CmdMod:from_map(Params) of
        {ok, Cmd} ->
            case HandlerMod:dispatch(Cmd) of
                ok                  -> {ok, #{status => accepted}};
                {ok, Result}        -> {ok, Result};
                {error, _} = E      -> E
            end;
        {error, _} = E ->
            E
    end.

%%% @doc Registers Macula RPC handlers for the capabilities
%%% advertised by `hecate_rag_service:capabilities/0`.
%%%
%%% Production traffic to hecate-rag flows over the mesh, not over
%%% HTTP. A plugin on a user laptop calls
%%%
%%%   macula:call(LocalStation, <<"hecate-rag.answer_query">>, Params, T)
%%%
%%% and the local macula-station routes the RPC to whichever
%%% infrastructure node is running hecate-rag. That node's
%%% hecate_rag_mesh_rpc worker has registered with the SDK to handle
%%% the method; it dispatches into the matching slice handler.
%%%
%%% Today: dispatch table only, no SDK wiring yet. When the
%%% `macula:advertise/3` call lands here, every capability the
%%% service declares becomes reachable across the realm.
-module(hecate_rag_mesh_rpc).
-behaviour(gen_server).

-export([start_link/0, dispatch/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Test/debug entry point that bypasses the SDK and dispatches
%% a request directly to the matching slice handler.
-spec dispatch(binary(), map()) -> {ok, term()} | {error, term()}.
dispatch(Method, Params) when is_binary(Method), is_map(Params) ->
    gen_server:call(?MODULE, {dispatch, Method, Params}).

init([]) ->
    %% TODO: hecate_om:macula_client/0 → for each capability in
    %% hecate_rag_service:capabilities/0:
    %%     macula:advertise(Client, Cap, ?MODULE).
    %% That makes inbound RPCs surface here as gen_server messages.
    {ok, #{}}.

handle_call({dispatch, Method, Params}, _From, S) ->
    {reply, route(Method, Params), S};
handle_call(_Msg, _From, S) ->
    {reply, {error, unknown_call}, S}.

handle_cast(_Msg, S) -> {noreply, S}.
handle_info(_Msg, S) -> {noreply, S}.
terminate(_Reason, _State) -> ok.

%%% Internal — method → slice handler

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

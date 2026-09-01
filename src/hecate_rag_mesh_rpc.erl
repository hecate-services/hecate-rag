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
    handle_upload_knowledge/1,
    handle_add_knowledge/1,
    handle_classify_topics/1,
    handle_prune_chunks/1,
    handle_answer_query/1,
    handle_rerank_results/1,
    handle_get_chunk_by_id/1,
    handle_search_chunks_semantic/1,
    handle_list_chunks_by_source/1,
    handle_get_source_by_id/1,
    handle_list_sources_page/1,
    handle_detect_corpus_change/1,
    handle_schedule_reembed/1
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
        {{ok, Pool}, {ok, Realm}} -> advertise_each(Pool, Realm);
        _                         -> ok
    end.

advertise_each(Pool, Realm) ->
    lists:foreach(fun(Entry) -> advertise_one(Pool, Realm, Entry) end, handler_table()).

advertise_one(Pool, Realm, {CapName, Handler}) ->
    try
        ok = macula:advertise(Pool, Realm, CapName, {?MODULE, Handler}, #{})
    catch _:_ -> ok
    end.

handler_table() ->
    [
        {<<"hecate-rag.ingest_document">>,        handle_ingest_document},
        {<<"hecate-rag.embed_document">>,         handle_embed_document},
        {<<"hecate-rag.upload_knowledge">>,       handle_upload_knowledge},
        {<<"hecate-rag.add_knowledge">>,          handle_add_knowledge},
        {<<"hecate-rag.classify_topics">>,        handle_classify_topics},
        {<<"hecate-rag.prune_chunks">>,           handle_prune_chunks},
        {<<"hecate-rag.answer_query">>,           handle_answer_query},
        {<<"hecate-rag.rerank_results">>,         handle_rerank_results},
        {<<"hecate-rag.get_chunk_by_id">>,        handle_get_chunk_by_id},
        {<<"hecate-rag.search_chunks_semantic">>, handle_search_chunks_semantic},
        {<<"hecate-rag.list_chunks_by_source">>,  handle_list_chunks_by_source},
        {<<"hecate-rag.get_source_by_id">>,       handle_get_source_by_id},
        {<<"hecate-rag.list_sources_page">>,      handle_list_sources_page},
        {<<"hecate-rag.detect_corpus_change">>,   handle_detect_corpus_change},
        {<<"hecate-rag.schedule_reembed">>,       handle_schedule_reembed}
    ].

%%% Internal: SDK handler entry points (one per capability)

handle_ingest_document(P)        -> route(<<"hecate-rag.ingest_document">>, P).
handle_embed_document(P)         -> route(<<"hecate-rag.embed_document">>, P).
handle_upload_knowledge(P)       -> route(<<"hecate-rag.upload_knowledge">>, P).
handle_add_knowledge(P)          -> route(<<"hecate-rag.add_knowledge">>, P).
handle_classify_topics(P)        -> route(<<"hecate-rag.classify_topics">>, P).
handle_prune_chunks(P)           -> route(<<"hecate-rag.prune_chunks">>, P).
handle_answer_query(P)           -> route(<<"hecate-rag.answer_query">>, P).
handle_rerank_results(P)         -> route(<<"hecate-rag.rerank_results">>, P).
handle_get_chunk_by_id(P)        -> route(<<"hecate-rag.get_chunk_by_id">>, P).
handle_search_chunks_semantic(P) -> route(<<"hecate-rag.search_chunks_semantic">>, P).
handle_list_chunks_by_source(P)  -> route(<<"hecate-rag.list_chunks_by_source">>, P).
handle_get_source_by_id(P)       -> route(<<"hecate-rag.get_source_by_id">>, P).
handle_list_sources_page(P)      -> route(<<"hecate-rag.list_sources_page">>, P).
handle_detect_corpus_change(P)   -> route(<<"hecate-rag.detect_corpus_change">>, P).
handle_schedule_reembed(P)       -> route(<<"hecate-rag.schedule_reembed">>, P).

%%% Internal: method → slice handler

route(<<"hecate-rag.ingest_document">>, P) ->
    maybe_ingest_document:ingest(P);
route(<<"hecate-rag.embed_document">>, P) ->
    maybe_embed_document:embed(P);
route(<<"hecate-rag.upload_knowledge">>, P) ->
    maybe_upload_knowledge:upload(P);
route(<<"hecate-rag.add_knowledge">>, P) ->
    maybe_add_knowledge:add(P);
route(<<"hecate-rag.classify_topics">>, P) ->
    maybe_classify_topics:classify(P);
route(<<"hecate-rag.prune_chunks">>, P) ->
    maybe_prune_chunks:prune(P);
route(<<"hecate-rag.answer_query">>, P) ->
    answer_query_result(maybe_answer_query:retrieve(P));
route(<<"hecate-rag.rerank_results">>, P) ->
    rerank_result(maybe_rerank_results:rerank(P));
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
route(<<"hecate-rag.detect_corpus_change">>, P) ->
    maybe_detect_corpus_change:detect(P);
route(<<"hecate-rag.schedule_reembed">>, P) ->
    maybe_schedule_reembed:schedule(P);
route(Other, _P) ->
    {error, {unknown_method, Other}}.

%% Both mirror their own HTTP handler's response shape (answer_query_api.erl/
%% rerank_results_api.erl), so a mesh caller and an HTTP caller see the same
%% contract for either.
answer_query_result({ok, Hits})    -> {ok, #{hits => Hits}};
answer_query_result({error, _} = E) -> E.

rerank_result({ok, Hits})    -> {ok, #{hits => Hits}};
rerank_result({error, _} = E) -> E.

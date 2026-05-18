%%% @doc Discovers Cowboy routes contributed by sibling umbrella
%%% apps under /api/v1/*. Each slice's *_api module exports a
%%% routes/0 function returning a Cowboy-style route list.
%%%
%%% This is the local admin / debug surface; production traffic
%%% comes via mesh RPC (see hecate_rag_mesh_rpc), not HTTP.
-module(hecate_rag_api_routes).

-export([discover_routes/0]).

-define(RAG_APPS, [
    rag,
    embed_corpus,
    refresh_corpus,
    serve_retrieval,
    query_chunks,
    query_sources
]).

%% @doc Walk every module in every umbrella app; collect routes/0 outputs.
-spec discover_routes() -> [tuple()].
discover_routes() ->
    lists:flatmap(fun routes_for_app/1, ?RAG_APPS).

%%% Internal

routes_for_app(App) ->
    case application:get_key(App, modules) of
        {ok, Modules} ->
            lists:flatmap(fun routes_for_module/1, Modules);
        undefined ->
            []
    end.

routes_for_module(Mod) ->
    case erlang:function_exported(Mod, routes, 0) of
        true ->
            try Mod:routes()
            catch _:_ -> []
            end;
        false ->
            []
    end.

%%% @doc Service-level root supervisor.
%%%
%%% Owns service-wide infrastructure that doesn't fit inside a
%%% single umbrella app:
%%%   - Cowboy HTTP listener (serves /health from hecate_om plus the
%%%     per-slice admin/debug routes under /api/v1/*)
%%%   - hecate_rag_mesh_rpc: registers the RPC handlers that back
%%%     the capabilities advertised by hecate_rag_service:capabilities/0
%%%
%%% The umbrella apps (embed_corpus, refresh_corpus, …) start
%%% themselves via their entries in hecate_rag.app.src.
-module(hecate_rag_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy  => one_for_one,
        intensity => 10,
        period    => 10
    },
    Children = [
        cowboy_child(),
        #{
            id       => hecate_rag_mesh_rpc,
            start    => {hecate_rag_mesh_rpc, start_link, []},
            restart  => permanent,
            shutdown => 5000,
            type     => worker,
            modules  => [hecate_rag_mesh_rpc]
        }
    ],
    {ok, {SupFlags, Children}}.

%%% Internal

cowboy_child() ->
    Port = application:get_env(hecate_rag, http_port, 8470),
    Dispatch = cowboy_router:compile(routes()),
    #{
        id       => cowboy_listener,
        start    => {cowboy, start_clear, [
            hecate_rag_http_listener,
            [{port, Port}],
            #{env => #{dispatch => Dispatch}}
        ]},
        restart  => permanent,
        shutdown => 5000,
        type     => worker,
        modules  => [cowboy]
    }.

routes() ->
    HealthRoutes = hecate_om_health_handler:routes(),
    ApiRoutes    = hecate_rag_api_routes:discover_routes(),
    [{'_', HealthRoutes ++ ApiRoutes}].

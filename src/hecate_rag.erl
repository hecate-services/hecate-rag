%%% @doc Public facade for hecate-rag.
%%%
%%% Used from the Erlang shell on an infrastructure node for
%%% admin / introspection. Programmatic consumers (other services,
%%% plugins on user laptops) reach the service via the mesh RPC
%%% capabilities advertised by `hecate_rag_service:capabilities/0`,
%%% not through this module.
-module(hecate_rag).

-export([
    info/0,
    health/0,
    capabilities/0,
    paths/0
]).

-spec info() -> map().
info() ->
    hecate_rag_service:info().

-spec health() -> hecate_om_service:health().
health() ->
    hecate_om:health().

-spec capabilities() -> [hecate_om_service:capability()].
capabilities() ->
    hecate_rag_service:capabilities().

-spec paths() -> map().
paths() ->
    #{
        data_dir  => application:get_env(hecate_rag, data_dir,  "/var/lib/hecate-rag/data"),
        index_dir => application:get_env(hecate_rag, index_dir, "/var/lib/hecate-rag/index")
    }.

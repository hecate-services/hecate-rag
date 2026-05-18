%%% @doc Smoke tests for hecate-rag.
-module(hecate_rag_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([service_info/1, capabilities_advertised/1, identity_spec_shape/1, mesh_rpc_dispatch_unknown/1]).

all() ->
    [service_info, capabilities_advertised, identity_spec_shape, mesh_rpc_dispatch_unknown].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(hecate_rag),
    Config.

end_per_suite(_Config) ->
    application:stop(hecate_rag),
    ok.

service_info(_Config) ->
    Info = hecate_rag_service:info(),
    ?assertEqual(<<"hecate-rag">>, maps:get(name, Info)),
    ?assert(is_binary(maps:get(version, Info))).

capabilities_advertised(_Config) ->
    Caps = hecate_rag_service:capabilities(),
    ?assert(length(Caps) >= 10),
    Names = [maps:get(name, C) || C <- Caps],
    ?assert(lists:member(<<"hecate-rag.answer_query">>, Names)),
    ?assert(lists:member(<<"hecate-rag.ingest_document">>, Names)).

identity_spec_shape(_Config) ->
    Spec = hecate_rag_service:identity_spec(),
    ?assertEqual(<<"hecate-rag">>, maps:get(scope, Spec)),
    ?assert(is_list(maps:get(actions, Spec))),
    ?assert(is_integer(maps:get(ttl_days, Spec))).

mesh_rpc_dispatch_unknown(_Config) ->
    ?assertMatch({error, {unknown_method, _}},
                 hecate_rag_mesh_rpc:dispatch(<<"hecate-rag.no_such_method">>, #{})).

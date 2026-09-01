%%% @doc Smoke tests for hecate-rag.
-module(hecate_rag_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([service_info/1, capabilities_advertised/1, identity_spec_shape/1, mesh_rpc_dispatch_unknown/1,
         corpus_git_sync_fast_forwards/1]).

all() ->
    [service_info, capabilities_advertised, identity_spec_shape, mesh_rpc_dispatch_unknown,
     corpus_git_sync_fast_forwards].

init_per_suite(Config) ->
    ok = rag_test_helpers:start_hecate_rag(),
    Config.

end_per_suite(_Config) ->
    rag_test_helpers:stop_hecate_rag().

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

%% End-to-end proof that the embedded Rust NIF actually loads and works
%% inside a real running hecate_rag application, not just in the crate's
%% own `cargo test' (which deliberately excludes the rustler wrapper --
%% see that crate's own lib.rs). Fixture repos are built with the real
%% `git' CLI here -- fine for test setup; the property being proved is
%% that PRODUCTION sync (corpus_git_sync -> hecate_rag_corpus_sync_nif)
%% needs no `git` binary at runtime, not that git tooling can never
%% exist anywhere in the test environment.
corpus_git_sync_fast_forwards(Config) ->
    TmpDir = ?config(priv_dir, Config),
    RemoteDir = filename:join(TmpDir, "remote.git"),
    LocalDir = filename:join(TmpDir, "local-checkout"),
    ok = git_init_bare(RemoteDir),
    ok = git_clone(RemoteDir, LocalDir),
    ok = git_commit_and_push(LocalDir, "corpus.md", "# v1\n", "initial"),

    ok = application:set_env(hecate_rag, corpus_root, LocalDir),

    ?assertEqual({ok, up_to_date}, corpus_git_sync:sync_now()),

    OtherClone = filename:join(TmpDir, "other-clone"),
    ok = git_clone(RemoteDir, OtherClone),
    ok = git_commit_and_push(OtherClone, "corpus.md", "# v2\n", "update"),

    ?assertMatch({ok, {fast_forwarded, _, _}}, corpus_git_sync:sync_now()),
    {ok, Content} = file:read_file(filename:join(LocalDir, "corpus.md")),
    ?assertEqual(<<"# v2\n">>, Content),

    ok = application:unset_env(hecate_rag, corpus_root).

%%% git fixture helpers -- shell out to the real git CLI, test-only.

git_init_bare(Dir) ->
    git_ok(io_lib:format("git init --bare -q ~s", [Dir])).

git_clone(From, To) ->
    git_ok(io_lib:format("git clone -q ~s ~s", [From, To])).

git_commit_and_push(Dir, FileName, Content, Message) ->
    ok = file:write_file(filename:join(Dir, FileName), Content),
    git_ok(io_lib:format(
        "git -C ~s add ~s && "
        "git -C ~s -c user.email=t@t -c user.name=t commit -q -m ~s && "
        "git -C ~s push -q origin HEAD",
        [Dir, FileName, Dir, Message, Dir]
    )).

git_ok(Cmd) ->
    Full = lists:flatten(Cmd),
    Output = os:cmd(Full ++ "; echo EXIT:$?"),
    check_exit(lists:suffix("EXIT:0\n", Output), Full, Output).

check_exit(true, _Full, _Output)  -> ok;
check_exit(false, Full, Output) -> error({git_command_failed, Full, Output}).

%%% @doc Periodic corpus git-sync, replacing the external bash-script-
%%% on-a-systemd-timer design. Every `?POLL_INTERVAL_MS' calls
%%% `hecate_rag_corpus_sync_nif:sync/1' against the configured corpus
%%% root (`corpus_root/0', app env `hecate_rag.corpus_root', defaulting
%%% to `/corpus') -- fetch `origin', fast-forward if possible, via
%%% vendored libgit2. No OS `git` binary involved, on the host or in
%%% the container.
%%%
%%% Lives here (service-level infrastructure, per `hecate_rag_sup''s
%%% own module doc), not inside `refresh_corpus': it calls
%%% `hecate_rag_corpus_sync_nif', a top-level app module, and this
%%% umbrella's own dependency direction runs from the top app into the
%%% sub-apps, never the reverse.
%%%
%%% Deliberately NOT coordinated with `refresh_corpus_scheduler' (the
%%% module that notices file changes and re-embeds): same
%%% "two independent, uncoordinated reconciliation loops, eventual
%%% consistency" shape this fleet's own GitOps already uses elsewhere
%%% (hecate-reconcile.timer + watchtower). This loop's only job is
%%% keeping the checkout current with git; noticing that files changed
%%% and re-embedding them is `refresh_corpus_scheduler''s own separate
%%% concern, on its own separate timer.
-module(corpus_git_sync).
-behaviour(gen_server).

-export([start_link/0, sync_now/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(POLL_INTERVAL_MS, 120000).

%% Overridable so a test can point this at a fixture checkout instead of
%% the real mount -- same convention `refresh_corpus_scheduler' uses.
corpus_root() ->
    application:get_env(hecate_rag, corpus_root, "/corpus").

-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Force an immediate sync, bypassing the timer. Same return shape
%% as `hecate_rag_corpus_sync_nif:sync/1', plus `{error, no_corpus_dir}'
%% when nothing is mounted at the configured root.
-spec sync_now() ->
    {ok, up_to_date | {fast_forwarded, binary(), binary()}} |
    {error, no_corpus_dir | not_fast_forward | {git_error, binary()}}.
sync_now() ->
    gen_server:call(?MODULE, sync_now, infinity).

init([]) ->
    schedule_tick(0),
    {ok, #{}}.

handle_call(sync_now, _From, State) ->
    {reply, do_sync(), State};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(tick, State) ->
    _ = do_sync(),
    schedule_tick(?POLL_INTERVAL_MS),
    {noreply, State};
handle_info(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%% Internals

schedule_tick(Delay) ->
    erlang:send_after(Delay, self(), tick).

do_sync() ->
    Root = corpus_root(),
    sync_root(filelib:is_dir(Root), Root).

%% Not every deployment mounts a corpus -- report it, don't crash on a
%% missing directory (same posture `refresh_corpus_scheduler' takes,
%% though that one skips quietly since it ticks far more often relative
%% to how rarely a corpus mount would actually be absent by mistake).
sync_root(false, _Root) ->
    {error, no_corpus_dir};
sync_root(true, Root) ->
    log_result(hecate_rag_corpus_sync_nif:sync(list_to_binary(Root))).

log_result({ok, up_to_date} = R) ->
    R;
log_result({ok, {fast_forwarded, From, To}} = R) ->
    logger:info("[corpus_git_sync] fast-forwarded ~s -> ~s", [From, To]),
    R;
log_result({error, not_fast_forward} = R) ->
    logger:warning("[corpus_git_sync] local checkout has diverged from origin -- left untouched"),
    R;
log_result({error, {git_error, Msg}} = R) ->
    logger:warning("[corpus_git_sync] git error: ~ts", [Msg]),
    R.

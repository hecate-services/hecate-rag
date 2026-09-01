%%% @doc Closes the loop `detect_corpus_change'/`schedule_reembed' left
%%% open: something has to actually walk the corpus and call them.
%%% Ticks every `?POLL_INTERVAL_MS', hashes every file under the
%%% configured corpus root (`corpus_root/0', defaulting to `/corpus',
%%% the container's actual mount point), and for each one whose hash
%%% differs from its last-known watermark:
%%%
%%%   1. Calls `maybe_schedule_reembed:schedule/1' to durably record the
%%%      request (the queue `schedule_reembed_v1' already exists for,
%%%      per its own module doc -- kept for the observability/audit
%%%      trail it gives, even though this same tick also does step 2).
%%%   2. Refreshes it immediately: `rag_store:upsert_source/1' with the
%%%      file's current bytes, then `maybe_embed_document:embed/1' --
%%%      which re-reads whatever `upsert_source' just wrote and
%%%      re-chunks/re-embeds from there. Works identically for a file
%%%      that already existed and one that never has (`upsert_source'
%%%      creates it either way), so there is no separate "new file"
%%%      branch.
%%%
%%% Deliberately immediate, not a separately-scheduled async drain: a
%%% markdown-sized re-ingest is cheap (barrel embeds synchronously in
%%% its own record-mode policy, same as every other write path here),
%%% so there is no real workload here that needs decoupling detection
%%% from processing across a durable backlog. If that changes, a
%%% consumer reading `type = reembed_request' records back out of
%%% `rag_store' is a natural, separate addition -- not built ahead of
%%% actually needing it.
%%%
%%% Independent of, and does not coordinate with, whatever keeps the
%%% corpus root itself in sync with git (a separate systemd timer on
%%% the host, outside this application) -- same "two uncoordinated
%%% reconciliation loops, eventual consistency" shape the rest of this
%%% fleet's GitOps already uses (hecate-reconcile.timer + watchtower).
-module(refresh_corpus_scheduler).
-behaviour(gen_server).

-export([start_link/0, scan/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(POLL_INTERVAL_MS, 120000).
-define(CORPUS_ID, <<"hecate-corpus">>).
-define(GLOB, "**/*.md").

%% Overridable so a test can point this at a fixture directory instead of
%% the real mount -- defaults to the container's actual mount point.
corpus_root() ->
    application:get_env(hecate_rag, corpus_root, "/corpus").

-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    schedule_tick(0),
    {ok, #{}}.

handle_info(tick, State) ->
    scan(),
    schedule_tick(?POLL_INTERVAL_MS),
    {noreply, State};
handle_info(_Msg, State) ->
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%% Internals

schedule_tick(Delay) ->
    erlang:send_after(Delay, self(), tick).

%% Synchronous and exported: the timer calls it every tick, an operator
%% or a test can call it directly to force an immediate rescan. Not
%% every deployment mounts a corpus -- skip quietly rather than erroring
%% on a missing directory.
-spec scan() -> ok.
scan() ->
    Root = corpus_root(),
    scan_root(filelib:is_dir(Root), Root).

scan_root(false, _Root) -> ok;
scan_root(true, Root) ->
    Files = filelib:wildcard(filename:join(Root, ?GLOB)),
    lists:foreach(fun(P) -> scan_file(Root, P) end, Files).

scan_file(Root, AbsPath) ->
    RelPath = relative_path(Root, AbsPath),
    case file:read_file(AbsPath) of
        {ok, Content} ->
            check_and_refresh(RelPath, Content);
        {error, Reason} ->
            logger:warning("[refresh_corpus_scheduler] read error path=~ts ~p", [RelPath, Reason])
    end.

%% Same trailing-slash normalization maybe_seed_corpus:ingest_file/3 uses --
%% needed here too since corpus_root/0 is caller/config-supplied and
%% could end in "/" (a test fixture directory easily might).
relative_path(RootDir, AbsPath) ->
    Prefix = string:trim(RootDir, trailing, "/") ++ "/",
    list_to_binary(string:replace(AbsPath, Prefix, "", leading)).

check_and_refresh(RelPath, Content) ->
    Hash = diff_hash(Content),
    Detect = #{<<"corpus_id">> => ?CORPUS_ID, <<"source_path">> => RelPath,
               <<"diff_hash">> => Hash},
    case maybe_detect_corpus_change:detect(Detect) of
        {ok, #{changed := true}}  -> refresh_changed(RelPath, Content);
        {ok, #{changed := false}} -> ok;
        {error, Reason} ->
            logger:warning("[refresh_corpus_scheduler] detect error path=~ts ~p", [RelPath, Reason])
    end.

refresh_changed(RelPath, Content) ->
    %% Best-effort record; {error, not_ingested} for a brand-new file is
    %% expected (nothing to schedule against yet) and not itself an error --
    %% refresh_file below ingests it regardless.
    _ = maybe_schedule_reembed:schedule(#{<<"corpus_id">> => ?CORPUS_ID,
                                           <<"source_path">> => RelPath}),
    refresh_file(RelPath, Content).

refresh_file(RelPath, Content) ->
    Source = #{
        document_id => RelPath, source_path => RelPath,
        source_type => <<"markdown">>, raw_bytes => Content
    },
    source_refreshed(rag_store:upsert_source(Source), RelPath).

source_refreshed(ok, RelPath) ->
    embed_refreshed(maybe_embed_document:embed(#{<<"document_id">> => RelPath}), RelPath);
source_refreshed({error, Reason}, RelPath) ->
    logger:warning("[refresh_corpus_scheduler] source store error path=~ts ~p", [RelPath, Reason]).

embed_refreshed({ok, _}, _RelPath) ->
    ok;
embed_refreshed({error, Reason}, RelPath) ->
    logger:warning("[refresh_corpus_scheduler] embed error path=~ts ~p", [RelPath, Reason]).

diff_hash(Content) ->
    binary:encode_hex(crypto:hash(sha256, Content)).

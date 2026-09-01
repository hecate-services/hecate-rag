%%% @doc Rustler NIF entry module.
%%%
%%% Loads `priv/lib/libhecate_rag_corpus_sync_nif.{so,dylib,dll}`. The
%%% Rust implementation lives in
%%% `native/hecate_rag_corpus_sync_nif/src/lib.rs' -- fetch `origin' for
%%% the checkout's current branch and fast-forward it, via vendored
%%% libgit2, no OS `git` binary involved. The Erlang body below is a
%%% placeholder that errors out if the NIF failed to load — it should
%%% never be hit at runtime.
-module(hecate_rag_corpus_sync_nif).

-export([sync/1]).

-on_load(init/0).

-define(NIF_NOT_LOADED, erlang:nif_error({nif_not_loaded, ?MODULE})).

-spec init() -> ok | {error, term()}.
init() ->
    PrivDir = case code:priv_dir(hecate_rag) of
        {error, _} ->
            %% Test / dev tree: rebar puts us in _build/.../hecate_rag/ebin
            EbinDir = filename:dirname(code:which(?MODULE)),
            filename:join(filename:dirname(EbinDir), "priv");
        Dir ->
            Dir
    end,
    SoPath = filename:join([PrivDir, "lib", "libhecate_rag_corpus_sync_nif"]),
    erlang:load_nif(SoPath, 0).

%% @doc Fetch `origin` for `Path`'s current branch and fast-forward it.
%% `{ok, up_to_date}' — nothing new. `{ok, {fast_forwarded, FromSha, ToSha}}'
%% — updated, working tree checked out to `ToSha'. `{error, not_fast_forward}'
%% — local and remote have diverged; left untouched, same safety property
%% `git pull --ff-only` has. `{error, {git_error, Message}}' — any other
%% libgit2 failure, with its own message text, not swallowed.
-spec sync(binary()) ->
    {ok, up_to_date | {fast_forwarded, binary(), binary()}} |
    {error, not_fast_forward | {git_error, binary()}}.
sync(_Path) -> ?NIF_NOT_LOADED.

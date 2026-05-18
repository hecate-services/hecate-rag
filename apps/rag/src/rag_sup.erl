%%% @doc Root supervisor for the shared `rag` app. Empty for now —
%%% lives here so sibling apps can list `rag` in their `applications`
%%% list and share future cross-cutting infrastructure.
-module(rag_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {
        #{strategy => one_for_one, intensity => 10, period => 10},
        []
    }}.

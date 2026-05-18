-module(project_sources_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {
        #{strategy => one_for_one, intensity => 10, period => 10},
        [#{id => document_ingested_v1_to_sources, start => {document_ingested_v1_to_sources, start_link, []}, restart => permanent, shutdown => 5000, type => worker, modules => [document_ingested_v1_to_sources]}]
    }}.

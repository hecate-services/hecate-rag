-module(project_chunks_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {
        #{strategy => one_for_one, intensity => 10, period => 10},
        [#{id => document_embedded_v1_to_chunks, start => {document_embedded_v1_to_chunks, start_link, []}, restart => permanent, shutdown => 5000, type => worker, modules => [document_embedded_v1_to_chunks]},
        #{id => chunks_pruned_v1_to_chunks, start => {chunks_pruned_v1_to_chunks, start_link, []}, restart => permanent, shutdown => 5000, type => worker, modules => [chunks_pruned_v1_to_chunks]}]
    }}.

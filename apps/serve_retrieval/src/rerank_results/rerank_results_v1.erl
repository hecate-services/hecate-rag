%%% @doc Command `rerank_results_v1`.
%%%
%%% Generated stub. Add validation in `maybe_rerank_results` once the slice
%%% has real business rules.
-module(rerank_results_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_query_id/1, get_original_ranking/1, get_reranker_model/1]).

-record(rerank_results_v1, {
    query_id :: binary() | undefined,
    original_ranking :: binary() | undefined,
    reranker_model :: binary() | undefined
}).

-opaque t() :: #rerank_results_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> rerank_results_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{query_id := Id} = Params) ->
    {ok, #rerank_results_v1{
        query_id = Id,
        original_ranking = maps:get(original_ranking, Params, undefined),
        reranker_model = maps:get(reranker_model, Params, undefined)
    }};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"query_id">> := Id} = Map) ->
    {ok, #rerank_results_v1{
        query_id = Id,
        original_ranking = maps:get(<<"original_ranking">>, Map, undefined),
        reranker_model = maps:get(<<"reranker_model">>, Map, undefined)
    }};
from_map(_) ->
    {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#rerank_results_v1{query_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#rerank_results_v1{} = Cmd) ->
    #{
        command_type => rerank_results_v1,
        query_id => Cmd#rerank_results_v1.query_id,
        original_ranking => Cmd#rerank_results_v1.original_ranking,
        reranker_model => Cmd#rerank_results_v1.reranker_model
    }.

-spec stream_id(t()) -> binary().
stream_id(#rerank_results_v1{query_id = Id}) ->
    <<"query-", Id/binary>>.

-spec get_query_id(t()) -> binary() | undefined.
get_query_id(#rerank_results_v1{query_id = V}) -> V.

-spec get_original_ranking(t()) -> binary() | undefined.
get_original_ranking(#rerank_results_v1{original_ranking = V}) -> V.

-spec get_reranker_model(t()) -> binary() | undefined.
get_reranker_model(#rerank_results_v1{reranker_model = V}) -> V.

%%% @doc Event `results_reranked_v1`.
-module(results_reranked_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_query_id/1, get_original_ranking/1, get_reranker_model/1]).

-record(results_reranked_v1, {
    query_id :: binary() | undefined,
    original_ranking :: binary() | undefined,
    reranker_model :: binary() | undefined
}).

-opaque t() :: #results_reranked_v1{}.
-export_type([t/0]).

event_type() -> results_reranked_v1.

-spec new(map()) -> {ok, t()}.
new(#{query_id := Id} = Params) ->
    {ok, #results_reranked_v1{
        query_id = Id,
        original_ranking = maps:get(original_ranking, Params, undefined),
        reranker_model = maps:get(reranker_model, Params, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"query_id">> := Id} = Map) ->
    {ok, #results_reranked_v1{
        query_id = Id,
        original_ranking = maps:get(<<"original_ranking">>, Map, undefined),
        reranker_model = maps:get(<<"reranker_model">>, Map, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#results_reranked_v1{} = Ev) ->
    #{
        event_type => results_reranked_v1,
        query_id => Ev#results_reranked_v1.query_id,
        original_ranking => Ev#results_reranked_v1.original_ranking,
        reranker_model => Ev#results_reranked_v1.reranker_model
    }.

get_query_id(#results_reranked_v1{query_id = V}) -> V.
get_original_ranking(#results_reranked_v1{original_ranking = V}) -> V.
get_reranker_model(#results_reranked_v1{reranker_model = V}) -> V.

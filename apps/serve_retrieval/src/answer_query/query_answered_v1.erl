%%% @doc Event `query_answered_v1`.
-module(query_answered_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_query_id/1, get_query_text/1, get_top_k/1, get_filters/1, get_hits/1]).

-record(query_answered_v1, {
    query_id :: binary() | undefined,
    query_text :: binary() | undefined,
    top_k :: binary() | undefined,
    filters :: binary() | undefined,
    hits :: binary() | undefined
}).

-opaque t() :: #query_answered_v1{}.
-export_type([t/0]).

event_type() -> query_answered_v1.

-spec new(map()) -> {ok, t()}.
new(#{query_id := Id} = Params) ->
    {ok, #query_answered_v1{
        query_id = Id,
        query_text = maps:get(query_text, Params, undefined),
        top_k = maps:get(top_k, Params, undefined),
        filters = maps:get(filters, Params, undefined),
        hits = maps:get(hits, Params, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"query_id">> := Id} = Map) ->
    {ok, #query_answered_v1{
        query_id = Id,
        query_text = maps:get(<<"query_text">>, Map, undefined),
        top_k = maps:get(<<"top_k">>, Map, undefined),
        filters = maps:get(<<"filters">>, Map, undefined),
        hits = maps:get(<<"hits">>, Map, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#query_answered_v1{} = Ev) ->
    #{
        event_type => query_answered_v1,
        query_id => Ev#query_answered_v1.query_id,
        query_text => Ev#query_answered_v1.query_text,
        top_k => Ev#query_answered_v1.top_k,
        filters => Ev#query_answered_v1.filters,
        hits => Ev#query_answered_v1.hits
    }.

get_query_id(#query_answered_v1{query_id = V}) -> V.
get_query_text(#query_answered_v1{query_text = V}) -> V.
get_top_k(#query_answered_v1{top_k = V}) -> V.
get_filters(#query_answered_v1{filters = V}) -> V.
get_hits(#query_answered_v1{hits = V}) -> V.

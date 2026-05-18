%%% @doc Event `reembed_scheduled_v1`.
-module(reembed_scheduled_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_corpus_id/1, get_source_path/1, get_priority/1, get_scheduled_at/1]).

-record(reembed_scheduled_v1, {
    corpus_id :: binary() | undefined,
    source_path :: binary() | undefined,
    priority :: binary() | undefined,
    scheduled_at :: binary() | undefined
}).

-opaque t() :: #reembed_scheduled_v1{}.
-export_type([t/0]).

event_type() -> reembed_scheduled_v1.

-spec new(map()) -> {ok, t()}.
new(#{corpus_id := Id} = Params) ->
    {ok, #reembed_scheduled_v1{
        corpus_id = Id,
        source_path = maps:get(source_path, Params, undefined),
        priority = maps:get(priority, Params, undefined),
        scheduled_at = maps:get(scheduled_at, Params, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"corpus_id">> := Id} = Map) ->
    {ok, #reembed_scheduled_v1{
        corpus_id = Id,
        source_path = maps:get(<<"source_path">>, Map, undefined),
        priority = maps:get(<<"priority">>, Map, undefined),
        scheduled_at = maps:get(<<"scheduled_at">>, Map, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#reembed_scheduled_v1{} = Ev) ->
    #{
        event_type => reembed_scheduled_v1,
        corpus_id => Ev#reembed_scheduled_v1.corpus_id,
        source_path => Ev#reembed_scheduled_v1.source_path,
        priority => Ev#reembed_scheduled_v1.priority,
        scheduled_at => Ev#reembed_scheduled_v1.scheduled_at
    }.

get_corpus_id(#reembed_scheduled_v1{corpus_id = V}) -> V.
get_source_path(#reembed_scheduled_v1{source_path = V}) -> V.
get_priority(#reembed_scheduled_v1{priority = V}) -> V.
get_scheduled_at(#reembed_scheduled_v1{scheduled_at = V}) -> V.

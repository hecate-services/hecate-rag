%%% @doc Event `corpus_change_detected_v1`.
-module(corpus_change_detected_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_corpus_id/1, get_source_path/1, get_kind/1, get_diff_hash/1]).

-record(corpus_change_detected_v1, {
    corpus_id :: binary() | undefined,
    source_path :: binary() | undefined,
    kind :: binary() | undefined,
    diff_hash :: binary() | undefined
}).

-opaque t() :: #corpus_change_detected_v1{}.
-export_type([t/0]).

event_type() -> corpus_change_detected_v1.

-spec new(map()) -> {ok, t()}.
new(#{corpus_id := Id} = Params) ->
    {ok, #corpus_change_detected_v1{
        corpus_id = Id,
        source_path = maps:get(source_path, Params, undefined),
        kind = maps:get(kind, Params, undefined),
        diff_hash = maps:get(diff_hash, Params, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"corpus_id">> := Id} = Map) ->
    {ok, #corpus_change_detected_v1{
        corpus_id = Id,
        source_path = maps:get(<<"source_path">>, Map, undefined),
        kind = maps:get(<<"kind">>, Map, undefined),
        diff_hash = maps:get(<<"diff_hash">>, Map, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#corpus_change_detected_v1{} = Ev) ->
    #{
        event_type => corpus_change_detected_v1,
        corpus_id => Ev#corpus_change_detected_v1.corpus_id,
        source_path => Ev#corpus_change_detected_v1.source_path,
        kind => Ev#corpus_change_detected_v1.kind,
        diff_hash => Ev#corpus_change_detected_v1.diff_hash
    }.

get_corpus_id(#corpus_change_detected_v1{corpus_id = V}) -> V.
get_source_path(#corpus_change_detected_v1{source_path = V}) -> V.
get_kind(#corpus_change_detected_v1{kind = V}) -> V.
get_diff_hash(#corpus_change_detected_v1{diff_hash = V}) -> V.

%%% @doc Event `chunks_pruned_v1`.
-module(chunks_pruned_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_document_id/1, get_chunk_ids/1, get_reason/1]).

-record(chunks_pruned_v1, {
    document_id :: binary() | undefined,
    chunk_ids :: binary() | undefined,
    reason :: binary() | undefined
}).

-opaque t() :: #chunks_pruned_v1{}.
-export_type([t/0]).

event_type() -> chunks_pruned_v1.

-spec new(map()) -> {ok, t()}.
new(#{document_id := Id} = Params) ->
    {ok, #chunks_pruned_v1{
        document_id = Id,
        chunk_ids = maps:get(chunk_ids, Params, undefined),
        reason = maps:get(reason, Params, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"document_id">> := Id} = Map) ->
    {ok, #chunks_pruned_v1{
        document_id = Id,
        chunk_ids = maps:get(<<"chunk_ids">>, Map, undefined),
        reason = maps:get(<<"reason">>, Map, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#chunks_pruned_v1{} = Ev) ->
    #{
        event_type => chunks_pruned_v1,
        document_id => Ev#chunks_pruned_v1.document_id,
        chunk_ids => Ev#chunks_pruned_v1.chunk_ids,
        reason => Ev#chunks_pruned_v1.reason
    }.

get_document_id(#chunks_pruned_v1{document_id = V}) -> V.
get_chunk_ids(#chunks_pruned_v1{chunk_ids = V}) -> V.
get_reason(#chunks_pruned_v1{reason = V}) -> V.

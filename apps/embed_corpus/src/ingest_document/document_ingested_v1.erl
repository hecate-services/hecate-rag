%%% @doc Event `document_ingested_v1`.
-module(document_ingested_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_document_id/1, get_source_path/1, get_source_type/1, get_raw_bytes/1]).

-record(document_ingested_v1, {
    document_id :: binary() | undefined,
    source_path :: binary() | undefined,
    source_type :: binary() | undefined,
    raw_bytes :: binary() | undefined
}).

-opaque t() :: #document_ingested_v1{}.
-export_type([t/0]).

event_type() -> document_ingested_v1.

-spec new(map()) -> {ok, t()}.
new(#{document_id := Id} = Params) ->
    {ok, #document_ingested_v1{
        document_id = Id,
        source_path = maps:get(source_path, Params, undefined),
        source_type = maps:get(source_type, Params, undefined),
        raw_bytes = maps:get(raw_bytes, Params, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"document_id">> := Id} = Map) ->
    {ok, #document_ingested_v1{
        document_id = Id,
        source_path = maps:get(<<"source_path">>, Map, undefined),
        source_type = maps:get(<<"source_type">>, Map, undefined),
        raw_bytes = maps:get(<<"raw_bytes">>, Map, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#document_ingested_v1{} = Ev) ->
    #{
        event_type => document_ingested_v1,
        document_id => Ev#document_ingested_v1.document_id,
        source_path => Ev#document_ingested_v1.source_path,
        source_type => Ev#document_ingested_v1.source_type,
        raw_bytes => Ev#document_ingested_v1.raw_bytes
    }.

get_document_id(#document_ingested_v1{document_id = V}) -> V.
get_source_path(#document_ingested_v1{source_path = V}) -> V.
get_source_type(#document_ingested_v1{source_type = V}) -> V.
get_raw_bytes(#document_ingested_v1{raw_bytes = V}) -> V.

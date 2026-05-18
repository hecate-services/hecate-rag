%%% @doc Command `ingest_document_v1`.
%%%
%%% Generated stub. Add validation in `maybe_ingest_document` once the slice
%%% has real business rules.
-module(ingest_document_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_document_id/1, get_source_path/1, get_source_type/1, get_raw_bytes/1]).

-record(ingest_document_v1, {
    document_id :: binary() | undefined,
    source_path :: binary() | undefined,
    source_type :: binary() | undefined,
    raw_bytes :: binary() | undefined
}).

-opaque t() :: #ingest_document_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> ingest_document_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{document_id := Id} = Params) ->
    {ok, #ingest_document_v1{
        document_id = Id,
        source_path = maps:get(source_path, Params, undefined),
        source_type = maps:get(source_type, Params, undefined),
        raw_bytes = maps:get(raw_bytes, Params, undefined)
    }};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"document_id">> := Id} = Map) ->
    {ok, #ingest_document_v1{
        document_id = Id,
        source_path = maps:get(<<"source_path">>, Map, undefined),
        source_type = maps:get(<<"source_type">>, Map, undefined),
        raw_bytes = maps:get(<<"raw_bytes">>, Map, undefined)
    }};
from_map(_) ->
    {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#ingest_document_v1{document_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#ingest_document_v1{} = Cmd) ->
    #{
        command_type => ingest_document_v1,
        document_id => Cmd#ingest_document_v1.document_id,
        source_path => Cmd#ingest_document_v1.source_path,
        source_type => Cmd#ingest_document_v1.source_type,
        raw_bytes => Cmd#ingest_document_v1.raw_bytes
    }.

-spec stream_id(t()) -> binary().
stream_id(#ingest_document_v1{document_id = Id}) ->
    <<"document-", Id/binary>>.

-spec get_document_id(t()) -> binary() | undefined.
get_document_id(#ingest_document_v1{document_id = V}) -> V.

-spec get_source_path(t()) -> binary() | undefined.
get_source_path(#ingest_document_v1{source_path = V}) -> V.

-spec get_source_type(t()) -> binary() | undefined.
get_source_type(#ingest_document_v1{source_type = V}) -> V.

-spec get_raw_bytes(t()) -> binary() | undefined.
get_raw_bytes(#ingest_document_v1{raw_bytes = V}) -> V.

%%% @doc Command `prune_chunks_v1`.
%%%
%%% Generated stub. Add validation in `maybe_prune_chunks` once the slice
%%% has real business rules.
-module(prune_chunks_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_document_id/1, get_chunk_ids/1, get_reason/1]).

-record(prune_chunks_v1, {
    document_id :: binary() | undefined,
    chunk_ids :: binary() | undefined,
    reason :: binary() | undefined
}).

-opaque t() :: #prune_chunks_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> prune_chunks_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{document_id := Id} = Params) ->
    {ok, #prune_chunks_v1{
        document_id = Id,
        chunk_ids = maps:get(chunk_ids, Params, undefined),
        reason = maps:get(reason, Params, undefined)
    }};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"document_id">> := Id} = Map) ->
    {ok, #prune_chunks_v1{
        document_id = Id,
        chunk_ids = maps:get(<<"chunk_ids">>, Map, undefined),
        reason = maps:get(<<"reason">>, Map, undefined)
    }};
from_map(_) ->
    {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#prune_chunks_v1{document_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#prune_chunks_v1{} = Cmd) ->
    #{
        command_type => prune_chunks_v1,
        document_id => Cmd#prune_chunks_v1.document_id,
        chunk_ids => Cmd#prune_chunks_v1.chunk_ids,
        reason => Cmd#prune_chunks_v1.reason
    }.

-spec stream_id(t()) -> binary().
stream_id(#prune_chunks_v1{document_id = Id}) ->
    <<"document-", Id/binary>>.

-spec get_document_id(t()) -> binary() | undefined.
get_document_id(#prune_chunks_v1{document_id = V}) -> V.

-spec get_chunk_ids(t()) -> binary() | undefined.
get_chunk_ids(#prune_chunks_v1{chunk_ids = V}) -> V.

-spec get_reason(t()) -> binary() | undefined.
get_reason(#prune_chunks_v1{reason = V}) -> V.

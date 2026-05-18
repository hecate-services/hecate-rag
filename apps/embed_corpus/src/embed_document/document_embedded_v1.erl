%%% @doc Event `document_embedded_v1`.
-module(document_embedded_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_document_id/1, get_chunks/1, get_model_id/1, get_dim/1]).

-record(document_embedded_v1, {
    document_id :: binary() | undefined,
    chunks :: binary() | undefined,
    model_id :: binary() | undefined,
    dim :: binary() | undefined
}).

-opaque t() :: #document_embedded_v1{}.
-export_type([t/0]).

event_type() -> document_embedded_v1.

-spec new(map()) -> {ok, t()}.
new(#{document_id := Id} = Params) ->
    {ok, #document_embedded_v1{
        document_id = Id,
        chunks = maps:get(chunks, Params, undefined),
        model_id = maps:get(model_id, Params, undefined),
        dim = maps:get(dim, Params, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"document_id">> := Id} = Map) ->
    {ok, #document_embedded_v1{
        document_id = Id,
        chunks = maps:get(<<"chunks">>, Map, undefined),
        model_id = maps:get(<<"model_id">>, Map, undefined),
        dim = maps:get(<<"dim">>, Map, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#document_embedded_v1{} = Ev) ->
    #{
        event_type => document_embedded_v1,
        document_id => Ev#document_embedded_v1.document_id,
        chunks => Ev#document_embedded_v1.chunks,
        model_id => Ev#document_embedded_v1.model_id,
        dim => Ev#document_embedded_v1.dim
    }.

get_document_id(#document_embedded_v1{document_id = V}) -> V.
get_chunks(#document_embedded_v1{chunks = V}) -> V.
get_model_id(#document_embedded_v1{model_id = V}) -> V.
get_dim(#document_embedded_v1{dim = V}) -> V.

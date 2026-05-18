%%% @doc Command `embed_document_v1`.
%%%
%%% Generated stub. Add validation in `maybe_embed_document` once the slice
%%% has real business rules.
-module(embed_document_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_document_id/1, get_chunks/1, get_model_id/1, get_dim/1]).

-record(embed_document_v1, {
    document_id :: binary() | undefined,
    chunks :: binary() | undefined,
    model_id :: binary() | undefined,
    dim :: binary() | undefined
}).

-opaque t() :: #embed_document_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> embed_document_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{document_id := Id} = Params) ->
    {ok, #embed_document_v1{
        document_id = Id,
        chunks = maps:get(chunks, Params, undefined),
        model_id = maps:get(model_id, Params, undefined),
        dim = maps:get(dim, Params, undefined)
    }};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"document_id">> := Id} = Map) ->
    {ok, #embed_document_v1{
        document_id = Id,
        chunks = maps:get(<<"chunks">>, Map, undefined),
        model_id = maps:get(<<"model_id">>, Map, undefined),
        dim = maps:get(<<"dim">>, Map, undefined)
    }};
from_map(_) ->
    {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#embed_document_v1{document_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#embed_document_v1{} = Cmd) ->
    #{
        command_type => embed_document_v1,
        document_id => Cmd#embed_document_v1.document_id,
        chunks => Cmd#embed_document_v1.chunks,
        model_id => Cmd#embed_document_v1.model_id,
        dim => Cmd#embed_document_v1.dim
    }.

-spec stream_id(t()) -> binary().
stream_id(#embed_document_v1{document_id = Id}) ->
    <<"document-", Id/binary>>.

-spec get_document_id(t()) -> binary() | undefined.
get_document_id(#embed_document_v1{document_id = V}) -> V.

-spec get_chunks(t()) -> binary() | undefined.
get_chunks(#embed_document_v1{chunks = V}) -> V.

-spec get_model_id(t()) -> binary() | undefined.
get_model_id(#embed_document_v1{model_id = V}) -> V.

-spec get_dim(t()) -> binary() | undefined.
get_dim(#embed_document_v1{dim = V}) -> V.

%%% @doc Command `answer_query_v1`.
%%%
%%% Generated stub. Add validation in `maybe_answer_query` once the slice
%%% has real business rules.
-module(answer_query_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_query_id/1, get_query_text/1, get_top_k/1, get_filters/1, get_hits/1]).

-record(answer_query_v1, {
    query_id :: binary() | undefined,
    query_text :: binary() | undefined,
    top_k :: binary() | undefined,
    filters :: binary() | undefined,
    hits :: binary() | undefined
}).

-opaque t() :: #answer_query_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> answer_query_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{query_id := Id} = Params) ->
    {ok, #answer_query_v1{
        query_id = Id,
        query_text = maps:get(query_text, Params, undefined),
        top_k = maps:get(top_k, Params, undefined),
        filters = maps:get(filters, Params, undefined),
        hits = maps:get(hits, Params, undefined)
    }};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"query_id">> := Id} = Map) ->
    {ok, #answer_query_v1{
        query_id = Id,
        query_text = maps:get(<<"query_text">>, Map, undefined),
        top_k = maps:get(<<"top_k">>, Map, undefined),
        filters = maps:get(<<"filters">>, Map, undefined),
        hits = maps:get(<<"hits">>, Map, undefined)
    }};
from_map(_) ->
    {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#answer_query_v1{query_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#answer_query_v1{} = Cmd) ->
    #{
        command_type => answer_query_v1,
        query_id => Cmd#answer_query_v1.query_id,
        query_text => Cmd#answer_query_v1.query_text,
        top_k => Cmd#answer_query_v1.top_k,
        filters => Cmd#answer_query_v1.filters,
        hits => Cmd#answer_query_v1.hits
    }.

-spec stream_id(t()) -> binary().
stream_id(#answer_query_v1{query_id = Id}) ->
    <<"query-", Id/binary>>.

-spec get_query_id(t()) -> binary() | undefined.
get_query_id(#answer_query_v1{query_id = V}) -> V.

-spec get_query_text(t()) -> binary() | undefined.
get_query_text(#answer_query_v1{query_text = V}) -> V.

-spec get_top_k(t()) -> binary() | undefined.
get_top_k(#answer_query_v1{top_k = V}) -> V.

-spec get_filters(t()) -> binary() | undefined.
get_filters(#answer_query_v1{filters = V}) -> V.

-spec get_hits(t()) -> binary() | undefined.
get_hits(#answer_query_v1{hits = V}) -> V.

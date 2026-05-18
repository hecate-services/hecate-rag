%%% @doc Command `schedule_reembed_v1`.
%%%
%%% Generated stub. Add validation in `maybe_schedule_reembed` once the slice
%%% has real business rules.
-module(schedule_reembed_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_corpus_id/1, get_source_path/1, get_priority/1, get_scheduled_at/1]).

-record(schedule_reembed_v1, {
    corpus_id :: binary() | undefined,
    source_path :: binary() | undefined,
    priority :: binary() | undefined,
    scheduled_at :: binary() | undefined
}).

-opaque t() :: #schedule_reembed_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> schedule_reembed_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{corpus_id := Id} = Params) ->
    {ok, #schedule_reembed_v1{
        corpus_id = Id,
        source_path = maps:get(source_path, Params, undefined),
        priority = maps:get(priority, Params, undefined),
        scheduled_at = maps:get(scheduled_at, Params, undefined)
    }};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"corpus_id">> := Id} = Map) ->
    {ok, #schedule_reembed_v1{
        corpus_id = Id,
        source_path = maps:get(<<"source_path">>, Map, undefined),
        priority = maps:get(<<"priority">>, Map, undefined),
        scheduled_at = maps:get(<<"scheduled_at">>, Map, undefined)
    }};
from_map(_) ->
    {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#schedule_reembed_v1{corpus_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#schedule_reembed_v1{} = Cmd) ->
    #{
        command_type => schedule_reembed_v1,
        corpus_id => Cmd#schedule_reembed_v1.corpus_id,
        source_path => Cmd#schedule_reembed_v1.source_path,
        priority => Cmd#schedule_reembed_v1.priority,
        scheduled_at => Cmd#schedule_reembed_v1.scheduled_at
    }.

-spec stream_id(t()) -> binary().
stream_id(#schedule_reembed_v1{corpus_id = Id}) ->
    <<"corpus-", Id/binary>>.

-spec get_corpus_id(t()) -> binary() | undefined.
get_corpus_id(#schedule_reembed_v1{corpus_id = V}) -> V.

-spec get_source_path(t()) -> binary() | undefined.
get_source_path(#schedule_reembed_v1{source_path = V}) -> V.

-spec get_priority(t()) -> binary() | undefined.
get_priority(#schedule_reembed_v1{priority = V}) -> V.

-spec get_scheduled_at(t()) -> binary() | undefined.
get_scheduled_at(#schedule_reembed_v1{scheduled_at = V}) -> V.

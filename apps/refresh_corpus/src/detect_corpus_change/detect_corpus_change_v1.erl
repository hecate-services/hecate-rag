%%% @doc Command `detect_corpus_change_v1`.
%%%
%%% Generated stub. Add validation in `maybe_detect_corpus_change` once the slice
%%% has real business rules.
-module(detect_corpus_change_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_corpus_id/1, get_source_path/1, get_kind/1, get_diff_hash/1]).

-record(detect_corpus_change_v1, {
    corpus_id :: binary() | undefined,
    source_path :: binary() | undefined,
    kind :: binary() | undefined,
    diff_hash :: binary() | undefined
}).

-opaque t() :: #detect_corpus_change_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> detect_corpus_change_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{corpus_id := Id} = Params) ->
    {ok, #detect_corpus_change_v1{
        corpus_id = Id,
        source_path = maps:get(source_path, Params, undefined),
        kind = maps:get(kind, Params, undefined),
        diff_hash = maps:get(diff_hash, Params, undefined)
    }};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"corpus_id">> := Id} = Map) ->
    {ok, #detect_corpus_change_v1{
        corpus_id = Id,
        source_path = maps:get(<<"source_path">>, Map, undefined),
        kind = maps:get(<<"kind">>, Map, undefined),
        diff_hash = maps:get(<<"diff_hash">>, Map, undefined)
    }};
from_map(_) ->
    {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#detect_corpus_change_v1{corpus_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#detect_corpus_change_v1{} = Cmd) ->
    #{
        command_type => detect_corpus_change_v1,
        corpus_id => Cmd#detect_corpus_change_v1.corpus_id,
        source_path => Cmd#detect_corpus_change_v1.source_path,
        kind => Cmd#detect_corpus_change_v1.kind,
        diff_hash => Cmd#detect_corpus_change_v1.diff_hash
    }.

-spec stream_id(t()) -> binary().
stream_id(#detect_corpus_change_v1{corpus_id = Id}) ->
    <<"corpus-", Id/binary>>.

-spec get_corpus_id(t()) -> binary() | undefined.
get_corpus_id(#detect_corpus_change_v1{corpus_id = V}) -> V.

-spec get_source_path(t()) -> binary() | undefined.
get_source_path(#detect_corpus_change_v1{source_path = V}) -> V.

-spec get_kind(t()) -> binary() | undefined.
get_kind(#detect_corpus_change_v1{kind = V}) -> V.

-spec get_diff_hash(t()) -> binary() | undefined.
get_diff_hash(#detect_corpus_change_v1{diff_hash = V}) -> V.

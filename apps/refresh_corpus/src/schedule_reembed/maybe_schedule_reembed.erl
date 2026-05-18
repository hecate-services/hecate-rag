%%% @doc Handler for `schedule_reembed_v1`. Validates the command and produces
%%% `reembed_scheduled_v1` as its outcome. Wire into evoq via
%%% `evoq:register_handler(schedule_reembed_v1, ?MODULE)` once business rules
%%% land here.
-module(maybe_schedule_reembed).

-export([handle/1, handle/2, dispatch/1]).

-spec handle(schedule_reembed_v1:t()) ->
    {ok, [reembed_scheduled_v1:t()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, undefined).

-spec handle(schedule_reembed_v1:t(), term()) ->
    {ok, [reembed_scheduled_v1:t()]} | {error, term()}.
handle(Cmd, _State) ->
    case schedule_reembed_v1:validate(Cmd) of
        ok ->
            {ok, Event} = reembed_scheduled_v1:new(#{
                corpus_id => schedule_reembed_v1:get_corpus_id(Cmd)
                %% TODO: copy relevant fields from Cmd into Event
            }),
            {ok, [Event]};
        {error, R} ->
            {error, R}
    end.

%% @doc Dispatch via evoq — persists the produced event(s).
-spec dispatch(schedule_reembed_v1:t()) -> ok | {error, term()}.
dispatch(Cmd) ->
    StreamId = schedule_reembed_v1:stream_id(Cmd),
    evoq:dispatch(rag_store, StreamId, Cmd, ?MODULE).

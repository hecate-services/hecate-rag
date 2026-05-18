%%% @doc Handler for `answer_query_v1`. Validates the command and produces
%%% `query_answered_v1` as its outcome. Wire into evoq via
%%% `evoq:register_handler(answer_query_v1, ?MODULE)` once business rules
%%% land here.
-module(maybe_answer_query).

-export([handle/1, handle/2, dispatch/1]).

-spec handle(answer_query_v1:t()) ->
    {ok, [query_answered_v1:t()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, undefined).

-spec handle(answer_query_v1:t(), term()) ->
    {ok, [query_answered_v1:t()]} | {error, term()}.
handle(Cmd, _State) ->
    case answer_query_v1:validate(Cmd) of
        ok ->
            {ok, Event} = query_answered_v1:new(#{
                query_id => answer_query_v1:get_query_id(Cmd)
                %% TODO: copy relevant fields from Cmd into Event
            }),
            {ok, [Event]};
        {error, R} ->
            {error, R}
    end.

%% @doc Dispatch via evoq — persists the produced event(s).
-spec dispatch(answer_query_v1:t()) -> ok | {error, term()}.
dispatch(Cmd) ->
    StreamId = answer_query_v1:stream_id(Cmd),
    evoq:dispatch(rag_store, StreamId, Cmd, ?MODULE).

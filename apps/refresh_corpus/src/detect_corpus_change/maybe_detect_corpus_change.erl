%%% @doc Handler for `detect_corpus_change_v1`. Validates the command and produces
%%% `corpus_change_detected_v1` as its outcome. Wire into evoq via
%%% `evoq:register_handler(detect_corpus_change_v1, ?MODULE)` once business rules
%%% land here.
-module(maybe_detect_corpus_change).

-export([handle/1, handle/2, dispatch/1]).

-spec handle(detect_corpus_change_v1:t()) ->
    {ok, [corpus_change_detected_v1:t()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, undefined).

-spec handle(detect_corpus_change_v1:t(), term()) ->
    {ok, [corpus_change_detected_v1:t()]} | {error, term()}.
handle(Cmd, _State) ->
    case detect_corpus_change_v1:validate(Cmd) of
        ok ->
            {ok, Event} = corpus_change_detected_v1:new(#{
                corpus_id => detect_corpus_change_v1:get_corpus_id(Cmd)
                %% TODO: copy relevant fields from Cmd into Event
            }),
            {ok, [Event]};
        {error, R} ->
            {error, R}
    end.

%% @doc Dispatch via evoq — persists the produced event(s).
-spec dispatch(detect_corpus_change_v1:t()) -> ok | {error, term()}.
dispatch(Cmd) ->
    StreamId = detect_corpus_change_v1:stream_id(Cmd),
    evoq:dispatch(rag_store, StreamId, Cmd, ?MODULE).

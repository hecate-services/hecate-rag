%%% @doc Handler for `rerank_results_v1`. Validates the command and produces
%%% `results_reranked_v1` as its outcome. Wire into evoq via
%%% `evoq:register_handler(rerank_results_v1, ?MODULE)` once business rules
%%% land here.
-module(maybe_rerank_results).

-export([handle/1, handle/2, dispatch/1]).

-spec handle(rerank_results_v1:t()) ->
    {ok, [results_reranked_v1:t()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, undefined).

-spec handle(rerank_results_v1:t(), term()) ->
    {ok, [results_reranked_v1:t()]} | {error, term()}.
handle(Cmd, _State) ->
    case rerank_results_v1:validate(Cmd) of
        ok ->
            {ok, Event} = results_reranked_v1:new(#{
                query_id => rerank_results_v1:get_query_id(Cmd)
                %% TODO: copy relevant fields from Cmd into Event
            }),
            {ok, [Event]};
        {error, R} ->
            {error, R}
    end.

%% @doc Dispatch via evoq — persists the produced event(s).
-spec dispatch(rerank_results_v1:t()) -> ok | {error, term()}.
dispatch(Cmd) ->
    StreamId = rerank_results_v1:stream_id(Cmd),
    evoq:dispatch(rag_store, StreamId, Cmd, ?MODULE).

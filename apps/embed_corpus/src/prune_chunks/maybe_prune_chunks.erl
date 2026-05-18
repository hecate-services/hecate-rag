%%% @doc Handler for `prune_chunks_v1`. Validates the command and produces
%%% `chunks_pruned_v1` as its outcome. Wire into evoq via
%%% `evoq:register_handler(prune_chunks_v1, ?MODULE)` once business rules
%%% land here.
-module(maybe_prune_chunks).

-export([handle/1, handle/2, dispatch/1]).

-spec handle(prune_chunks_v1:t()) ->
    {ok, [chunks_pruned_v1:t()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, undefined).

-spec handle(prune_chunks_v1:t(), term()) ->
    {ok, [chunks_pruned_v1:t()]} | {error, term()}.
handle(Cmd, _State) ->
    case prune_chunks_v1:validate(Cmd) of
        ok ->
            {ok, Event} = chunks_pruned_v1:new(#{
                document_id => prune_chunks_v1:get_document_id(Cmd)
                %% TODO: copy relevant fields from Cmd into Event
            }),
            {ok, [Event]};
        {error, R} ->
            {error, R}
    end.

%% @doc Dispatch via evoq — persists the produced event(s).
-spec dispatch(prune_chunks_v1:t()) -> ok | {error, term()}.
dispatch(Cmd) ->
    StreamId = prune_chunks_v1:stream_id(Cmd),
    evoq:dispatch(rag_store, StreamId, Cmd, ?MODULE).

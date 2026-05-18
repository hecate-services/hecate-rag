%%% @doc Handler for `embed_document_v1`. Validates the command and produces
%%% `document_embedded_v1` as its outcome. Wire into evoq via
%%% `evoq:register_handler(embed_document_v1, ?MODULE)` once business rules
%%% land here.
-module(maybe_embed_document).

-export([handle/1, handle/2, dispatch/1]).

-spec handle(embed_document_v1:t()) ->
    {ok, [document_embedded_v1:t()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, undefined).

-spec handle(embed_document_v1:t(), term()) ->
    {ok, [document_embedded_v1:t()]} | {error, term()}.
handle(Cmd, _State) ->
    case embed_document_v1:validate(Cmd) of
        ok ->
            {ok, Event} = document_embedded_v1:new(#{
                document_id => embed_document_v1:get_document_id(Cmd)
                %% TODO: copy relevant fields from Cmd into Event
            }),
            {ok, [Event]};
        {error, R} ->
            {error, R}
    end.

%% @doc Dispatch via evoq — persists the produced event(s).
-spec dispatch(embed_document_v1:t()) -> ok | {error, term()}.
dispatch(Cmd) ->
    StreamId = embed_document_v1:stream_id(Cmd),
    evoq:dispatch(rag_store, StreamId, Cmd, ?MODULE).

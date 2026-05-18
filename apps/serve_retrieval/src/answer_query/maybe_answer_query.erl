%%% @doc Handler for `answer_query_v1`.
%%%
%%% Two concerns:
%%%
%%%   1. Produce the `query_answered_v1' event for the event store
%%%      (audit trail of what was asked + what came back).
%%%   2. Return the hits to the caller, so the federation responder
%%%      (and the local API handler) can pass them up.
%%%
%%% Delegates the actual retrieval to the `search_chunks_semantic'
%%% query desk, which embeds the query text + searches the vector
%%% index + enriches hits with content from the SQLite read model.
-module(maybe_answer_query).

-export([handle/1, handle/2, dispatch/1, retrieve/1]).

-spec handle(answer_query_v1:t()) ->
    {ok, [query_answered_v1:t()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, undefined).

-spec handle(answer_query_v1:t(), term()) ->
    {ok, [query_answered_v1:t()]} | {error, term()}.
handle(Cmd, _State) ->
    case answer_query_v1:validate(Cmd) of
        ok ->
            QueryText = answer_query_v1:get_query_text(Cmd),
            TopK      = answer_query_v1:get_top_k(Cmd),
            Hits = case do_search(QueryText, TopK) of
                {ok, H} -> H;
                _       -> []
            end,
            {ok, Event} = query_answered_v1:new(#{
                query_id   => answer_query_v1:get_query_id(Cmd),
                query_text => QueryText,
                top_k      => TopK,
                hits       => Hits
            }),
            {ok, [Event]};
        {error, R} ->
            {error, R}
    end.

%% @doc Convenience entry for callers that don't care about the
%% event — returns hits directly. Used by hecate_rag_federation to
%% fill macula_rag's response payload.
-spec retrieve(map()) -> {ok, [map()]} | {error, term()}.
retrieve(Params) when is_map(Params) ->
    search_chunks_semantic:handle(Params).

%% @doc Dispatch via evoq — persists the produced event(s).
-spec dispatch(answer_query_v1:t()) -> ok | {error, term()}.
dispatch(Cmd) ->
    StreamId = answer_query_v1:stream_id(Cmd),
    evoq:dispatch(rag_store, StreamId, Cmd, ?MODULE).

%%% Internals

do_search(undefined, _TopK) ->
    {ok, []};
do_search(<<>>, _TopK) ->
    {ok, []};
do_search(QueryText, TopK0) when is_binary(QueryText) ->
    TopK = case TopK0 of
        N when is_integer(N), N > 0 -> N;
        _                            -> 10
    end,
    search_chunks_semantic:handle(#{
        <<"query_text">> => QueryText,
        <<"top_k">>      => TopK
    }).

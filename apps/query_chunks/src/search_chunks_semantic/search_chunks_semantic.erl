%%% @doc Query desk: search_chunks_semantic.
%%%
%%% Takes a query (text OR pre-computed vector) + top_k, returns
%%% the top-k chunk hits enriched with content and source-path.
%%%
%%% Two call shapes accepted:
%%%
%%%   #{<<"query_text">> := Text, <<"top_k">> := N}
%%%       text → hecate_embed:embed → rag_store:search
%%%
%%%   #{<<"query_vector">> := [Float], <<"top_k">> := N}
%%%       use the provided vector directly (caller already embedded)
%%%
%%% Both forms accept an optional `top_k` field, default 10.
-module(search_chunks_semantic).

-export([handle/1]).

-define(DEFAULT_TOP_K, 10).

-spec handle(map()) -> {ok, [map()]} | {error, term()}.
handle(Params) when is_map(Params) ->
    TopK = top_k(Params),
    case query_vector(Params) of
        {ok, Vector} ->
            rag_store:search(Vector, TopK);
        {error, _} = E ->
            E
    end;
handle(_) ->
    {error, bad_params}.

%%% Internals

query_vector(#{<<"query_vector">> := V}) when is_list(V) ->
    {ok, V};
query_vector(#{<<"query_text">> := Text}) when is_binary(Text) ->
    case hecate_embed:embed(Text) of
        {ok, V}        -> {ok, V};
        {error, _} = E -> E
    end;
query_vector(_) ->
    {error, query_text_or_vector_required}.

top_k(#{<<"top_k">> := N}) when is_integer(N), N > 0, N =< 100 -> N;
top_k(_)                                                       -> ?DEFAULT_TOP_K.

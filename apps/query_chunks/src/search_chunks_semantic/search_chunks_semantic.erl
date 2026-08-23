%%% @doc Query desk: search_chunks_semantic.
%%%
%%% Takes a query (text OR pre-computed vector) + top_k, returns
%%% the top-k chunk hits enriched with content and source-path.
%%%
%%% Two call shapes accepted:
%%%
%%%   #{<<"query_text">> := Text, <<"top_k">> := N}
%%%       barrel embeds the query itself (record-mode database, see
%%%       rag_store) — no separate embed call needed here.
%%%
%%%   #{<<"query_vector">> := [Float], <<"top_k">> := N}
%%%       use the provided vector directly (caller already embedded)
%%%
%%% Both forms accept an optional `top_k` field, default 10.
-module(search_chunks_semantic).

-export([handle/1]).

-define(DEFAULT_TOP_K, 10).

-spec handle(map()) -> {ok, [map()]} | {error, term()}.
handle(#{<<"query_vector">> := V} = Params) when is_list(V) ->
    rag_store:search_vector(V, top_k(Params));
handle(#{<<"query_text">> := Text} = Params) when is_binary(Text) ->
    rag_store:search_text(Text, top_k(Params));
handle(Params) when is_map(Params) ->
    {error, query_text_or_vector_required};
handle(_) ->
    {error, bad_params}.

top_k(#{<<"top_k">> := N}) when is_integer(N), N > 0, N =< 100 -> N;
top_k(_)                                                       -> ?DEFAULT_TOP_K.

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
%%%
%%% Optional `<<"topics">> := [binary()]` filters results to chunks
%%% tagged with any of the given topics. Over-fetches from the vector
%%% index (3x top_k) then post-filters by topic metadata, returning the
%%% top_k best matches that pass the filter.
-module(search_chunks_semantic).

-export([handle/1]).

-define(DEFAULT_TOP_K, 10).
-define(TOPIC_OVERFETCH_MULTIPLIER, 3).

-spec handle(map()) -> {ok, [map()]} | {error, term()}.
handle(#{<<"query_vector">> := V} = Params) when is_list(V) ->
    search_with_topics(Params, fun() -> rag_store:search_vector(V, fetch_k(Params)) end);
handle(#{<<"query_text">> := Text} = Params) when is_binary(Text) ->
    search_with_topics(Params, fun() -> rag_store:search_text(Text, fetch_k(Params)) end);
handle(Params) when is_map(Params) ->
    {error, query_text_or_vector_required};
handle(_) ->
    {error, bad_params}.

search_with_topics(Params, SearchFun) ->
    case SearchFun() of
        {ok, Hits} ->
            Filtered = maybe_filter_by_topics(Hits, Params),
            {ok, lists:sublist(Filtered, top_k(Params))};
        {error, _} = E ->
            E
    end.

maybe_filter_by_topics(Hits, #{<<"topics">> := Topics}) when is_list(Topics), Topics =/= [] ->
    TopicSet = sets:from_list([normalize_topic(T) || T <- Topics]),
    [H || H <- Hits, has_any_topic(H, TopicSet)];
maybe_filter_by_topics(Hits, _Params) ->
    Hits.

has_any_topic(Hit, TopicSet) ->
    Meta = maps:get(meta, Hit, #{}),
    Topics = maps:get(<<"topics">>, Meta, []),
    ChunkTopics = sets:from_list([normalize_topic(T) || T <- Topics]),
    not sets:is_empty(sets:intersection(TopicSet, ChunkTopics)).

normalize_topic(T) when is_binary(T) -> string:lowercase(string:trim(T));
normalize_topic(T) when is_list(T)   -> normalize_topic(list_to_binary(T)).

%% When filtering by topics, over-fetch from the vector index so the
%% post-filter still has enough candidates to fill top_k. Without a
%% topic filter, fetch exactly top_k.
fetch_k(#{<<"topics">> := Topics} = Params) when is_list(Topics), Topics =/= [] ->
    top_k(Params) * ?TOPIC_OVERFETCH_MULTIPLIER;
fetch_k(Params) ->
    top_k(Params).

top_k(#{<<"top_k">> := N}) when is_integer(N), N > 0, N =< 100 -> N;
top_k(_)                                                       -> ?DEFAULT_TOP_K.

%%% @doc Query desk: list_sources_page. Returns a page of results, newest
%%% ingested first (delegates to rag_store).
-module(list_sources_page).

-export([handle/1]).

-define(DEFAULT_LIMIT, 50).
-define(MAX_LIMIT, 200).

-spec handle(map()) -> {ok, [map()]} | {error, term()}.
handle(Params) when is_map(Params) ->
    rag_store:list_sources(offset(Params), limit(Params)).

offset(#{<<"offset">> := O}) -> to_non_neg_int(O, 0);
offset(_)                    -> 0.

limit(#{<<"limit">> := L}) -> min(to_pos_int(L, ?DEFAULT_LIMIT), ?MAX_LIMIT);
limit(_)                   -> ?DEFAULT_LIMIT.

to_pos_int(Bin, Default) ->
    case to_int(Bin) of
        N when is_integer(N), N > 0 -> N;
        _                            -> Default
    end.

to_non_neg_int(Bin, Default) ->
    case to_int(Bin) of
        N when is_integer(N), N >= 0 -> N;
        _                             -> Default
    end.

to_int(Bin) ->
    try binary_to_integer(Bin) catch _:_ -> undefined end.

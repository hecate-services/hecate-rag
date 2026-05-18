%%% @doc Query desk: search_chunks_semantic. Returns a page of results.
-module(search_chunks_semantic).

-export([handle/1]).

-spec handle(map()) -> {ok, [map()]} | {error, term()}.
handle(_Params) ->
    %% TODO: SELECT page from SQLite read model.
    {ok, []}.

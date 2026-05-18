%%% @doc Query desk: list_chunks_by_source. Returns a page of results.
-module(list_chunks_by_source).

-export([handle/1]).

-spec handle(map()) -> {ok, [map()]} | {error, term()}.
handle(_Params) ->
    %% TODO: SELECT page from SQLite read model.
    {ok, []}.

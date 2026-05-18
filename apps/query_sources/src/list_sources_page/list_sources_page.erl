%%% @doc Query desk: list_sources_page. Returns a page of results.
-module(list_sources_page).

-export([handle/1]).

-spec handle(map()) -> {ok, [map()]} | {error, term()}.
handle(_Params) ->
    %% TODO: SELECT page from SQLite read model.
    {ok, []}.

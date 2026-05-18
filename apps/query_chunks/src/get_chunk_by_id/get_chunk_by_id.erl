%%% @doc Query desk: get_chunk_by_id. Looks up by id from the read model.
-module(get_chunk_by_id).

-export([handle/1]).

-spec handle(binary()) -> {ok, map()} | {error, term()}.
handle(_Id) ->
    %% TODO: SELECT from SQLite read model via esqlite.
    {error, not_implemented}.

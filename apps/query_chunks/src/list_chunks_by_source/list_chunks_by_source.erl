%%% @doc Query desk: list_chunks_by_source. Every chunk recorded against a
%%% given `source_path' (delegates to rag_store).
-module(list_chunks_by_source).

-export([handle/1]).

-define(DEFAULT_LIMIT, 100).
-define(MAX_LIMIT, 500).

-spec handle(map()) -> {ok, [map()]} | {error, term()}.
handle(#{<<"source_path">> := SourcePath} = Params)
  when is_binary(SourcePath), SourcePath =/= <<>> ->
    rag_store:list_chunks_by_source(SourcePath, limit(Params));
handle(_Params) ->
    {error, missing_source_path}.

limit(#{<<"limit">> := L}) -> min(to_pos_int(L), ?MAX_LIMIT);
limit(_)                   -> ?DEFAULT_LIMIT.

to_pos_int(Bin) ->
    case (catch binary_to_integer(Bin)) of
        N when is_integer(N), N > 0 -> N;
        _                            -> ?DEFAULT_LIMIT
    end.

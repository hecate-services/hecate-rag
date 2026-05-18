%%% @doc Cowboy handler — GET /api/rag/chunks/by-source.
-module(list_chunks_by_source_api).

-export([init/2, routes/0]).

routes() -> [{"/api/rag/chunks/by-source", ?MODULE, []}].

init(Req0, _State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            Params = maps:from_list(cowboy_req:parse_qs(Req0)),
            case list_chunks_by_source:handle(Params) of
                {ok, Items} ->
                    hecate_rag_http:ok_json(#{items => Items}, Req0);
                {error, Reason} ->
                    hecate_rag_http:bad_request(
                        iolist_to_binary(io_lib:format("~p", [Reason])), Req0)
            end;
        _ ->
            hecate_rag_http:method_not_allowed(Req0)
    end.

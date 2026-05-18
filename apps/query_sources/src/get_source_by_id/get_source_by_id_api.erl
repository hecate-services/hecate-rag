%%% @doc Cowboy handler — GET /api/rag/sources/:source_id.
-module(get_source_by_id_api).

-export([init/2, routes/0]).

routes() -> [{"/api/rag/sources/:source_id", ?MODULE, []}].

init(Req0, _State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            Id = cowboy_req:binding(source_id, Req0),
            case get_source_by_id:handle(Id) of
                {ok, Result} ->
                    hecate_rag_http:ok_json(Result, Req0);
                {error, not_found} ->
                    hecate_rag_http:not_found(Req0);
                {error, Reason} ->
                    hecate_rag_http:bad_request(
                        iolist_to_binary(io_lib:format("~p", [Reason])), Req0)
            end;
        _ ->
            hecate_rag_http:method_not_allowed(Req0)
    end.

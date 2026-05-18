%%% @doc Cowboy handler — POST /api/rag/documents/embed.
-module(embed_document_api).

-export([init/2, routes/0]).

routes() -> [{"/api/rag/documents/embed", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle(Req0, State);
        _                  -> hecate_rag_http:method_not_allowed(Req0)
    end.

handle(Req0, _State) ->
    case hecate_rag_http:read_json_body(Req0) of
        {ok, Params, Req1} ->
            case embed_document_v1:from_map(Params) of
                {ok, Cmd} ->
                    case maybe_embed_document:dispatch(Cmd) of
                        ok ->
                            hecate_rag_http:ok_json(#{status => accepted}, Req1);
                        {error, Reason} ->
                            hecate_rag_http:bad_request(reason_to_bin(Reason), Req1)
                    end;
                {error, Reason} ->
                    hecate_rag_http:bad_request(reason_to_bin(Reason), Req1)
            end;
        {error, invalid_json, Req1} ->
            hecate_rag_http:bad_request(<<"Invalid JSON">>, Req1)
    end.

reason_to_bin(R) when is_atom(R)   -> atom_to_binary(R, utf8);
reason_to_bin(R) when is_binary(R) -> R;
reason_to_bin(R)                   -> iolist_to_binary(io_lib:format("~p", [R])).

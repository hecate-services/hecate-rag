%%% @doc hecate-rag OTP application entry.
-module(hecate_rag_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    hecate_om:boot(hecate_rag_service).

stop(_State) ->
    ok.

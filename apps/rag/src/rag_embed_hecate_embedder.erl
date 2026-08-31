%%%-------------------------------------------------------------------
%%% @doc barrel_embed provider backed by hecate-embedder over the mesh.
%%%
%%% Embedding needs an ONNX runtime (AVX2); the beam Celerons this
%%% service is deployed on don't have it. hecate-embedder already
%%% solves exactly this for the rest of the society (Spartan's own
%%% long-term memory reaches it the same way) -- this module is the
%%% barrel_embed_provider adapter, not a new embedding path.
%%%
%%% == Configuration ==
%%% ```
%%% Config = #{
%%%     dimension => 384,   %% hecate-embed's multilingual-e5-small
%%%     timeout   => 30000  %% mesh call timeout, ms
%%% }.
%%% '''
%%%
%%% `kind' is deliberately fixed to `raw' (no query/passage prefix),
%%% matching the symmetric behavior barrel_embed_ollama already had --
%%% hecate-rag's own callers (barrel:search/3) never distinguished
%%% query vs. passage embedding either. Wiring the asymmetric prefix
%%% through would improve retrieval quality but is a real, separate
%%% decision (needs a kind hint threaded from rag_store's query path),
%%% not made here.
%%% @end
%%%-------------------------------------------------------------------
-module(rag_embed_hecate_embedder).
-behaviour(barrel_embed_provider).

-export([embed/2, embed_batch/2, dimension/1, name/0, init/1]).

-define(CAPABILITY, <<"io.hecate.embed">>).
-define(DEFAULT_DIMENSION, 384).
-define(DEFAULT_TIMEOUT, 30000).

%%====================================================================
%% Behaviour callbacks
%%====================================================================

name() -> hecate_embedder.

dimension(Config) ->
    maps:get(dimension, Config, ?DEFAULT_DIMENSION).

init(Config) ->
    {ok, maps:merge(#{dimension => ?DEFAULT_DIMENSION,
                       timeout   => ?DEFAULT_TIMEOUT}, Config)}.

-spec embed(binary(), map()) -> {ok, [float()]} | {error, term()}.
embed(Text, Config) ->
    Timeout = maps:get(timeout, Config, ?DEFAULT_TIMEOUT),
    case mesh_call(#{text => Text, kind => raw}, Timeout) of
        {ok, #{<<"vector">> := Vector}} -> {ok, Vector};
        {ok, #{vector := Vector}}       -> {ok, Vector};
        {ok, Other}                     -> {error, {invalid_response, Other}};
        {error, _} = Error              -> Error
    end.

-spec embed_batch([binary()], map()) -> {ok, [[float()]]} | {error, term()}.
embed_batch(Texts, Config) ->
    Timeout = maps:get(timeout, Config, ?DEFAULT_TIMEOUT),
    case mesh_call(#{texts => Texts}, Timeout) of
        {ok, #{<<"vectors">> := Vectors}} -> {ok, Vectors};
        {ok, #{vectors := Vectors}}       -> {ok, Vectors};
        {ok, Other}                       -> {error, {invalid_response, Other}};
        {error, _} = Error                -> Error
    end.

%%====================================================================
%% Internal
%%====================================================================

mesh_call(Payload, Timeout) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            macula:call(Pool, Realm, ?CAPABILITY, Payload, Timeout);
        {{error, Reason}, _} ->
            {error, {no_mesh_client, Reason}};
        {_, {error, Reason}} ->
            {error, {no_realm, Reason}}
    end.

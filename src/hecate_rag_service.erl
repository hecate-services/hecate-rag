%%% @doc hecate-rag — implements the hecate_om_service behaviour.
%%%
%%% Lifecycle, health, capabilities, identity. The actual supervisory
%%% root lives in hecate_rag_sup; the per-slice OTP apps boot
%%% independently via the `applications` list in hecate_rag.app.src.
-module(hecate_rag_service).
-behaviour(hecate_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).

info() ->
    #{
        name        => <<"hecate-rag">>,
        version     => <<"0.1.0">>,
        description => <<"Realm-bound RAG service: retrieval over the configured corpora">>
    }.

start(_Opts) ->
    hecate_rag_sup:start_link().

stop(_State) ->
    ok.

%% @doc Composite health check.
%% - vector index reachable?
%% - embedder model loaded?
%% - SQLite read models open?
%% Today: scaffolded `ok`. Real probe lands as the apps wire up.
health() ->
    ok.

%% @doc Advertised onto the mesh bloom-channel by hecate_om_capabilities.
capabilities() ->
    [
        #{name => <<"hecate-rag.ingest_document">>,         version => 1},
        #{name => <<"hecate-rag.embed_document">>,          version => 1},
        #{name => <<"hecate-rag.prune_chunks">>,            version => 1},
        #{name => <<"hecate-rag.answer_query">>,            version => 1},
        #{name => <<"hecate-rag.rerank_results">>,          version => 1},
        #{name => <<"hecate-rag.get_chunk_by_id">>,         version => 1},
        #{name => <<"hecate-rag.search_chunks_semantic">>,  version => 1},
        #{name => <<"hecate-rag.list_chunks_by_source">>,   version => 1},
        #{name => <<"hecate-rag.get_source_by_id">>,        version => 1},
        #{name => <<"hecate-rag.list_sources_page">>,       version => 1}
    ].

%% @doc Realm-issued service-principal scope. hecate-realm mints a
%% credential matching this at provision time.
identity_spec() ->
    #{
        scope     => <<"hecate-rag">>,
        actions   => [
            <<"publish_summary">>,
            <<"answer_query">>,
            <<"advertise_capability">>,
            <<"read_corpus">>
        ],
        resources => [
            <<"corpora/*">>,
            <<"hecate-rag/*">>
        ],
        ttl_days  => 365
    }.

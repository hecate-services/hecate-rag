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
        version     => <<"0.1.7">>,
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

%% @doc Advertised onto the mesh bloom-channel by hecate_om_capabilities,
%% and — via each entry's `handler' key — actually callable through it
%% too (`hecate_om_simple_handler' bridges to `hecate_rag_mesh_rpc''s own
%% one-arity handler functions, so their `route/2' dispatch logic is
%% unchanged). No capability here sets `auth': all 15 stay open. See
%% `plans/PLAN_UCAN_GATED_CAPABILITIES.md' for `prune_chunks' and
%% `schedule_reembed' as gating candidates, not yet decided.
capabilities() ->
    [
        cap(<<"hecate-rag.ingest_document">>,        handle_ingest_document),
        cap(<<"hecate-rag.embed_document">>,         handle_embed_document),
        cap(<<"hecate-rag.upload_knowledge">>,       handle_upload_knowledge),
        cap(<<"hecate-rag.add_knowledge">>,          handle_add_knowledge),
        cap(<<"hecate-rag.classify_topics">>,        handle_classify_topics),
        cap(<<"hecate-rag.prune_chunks">>,           handle_prune_chunks),
        cap(<<"hecate-rag.answer_query">>,           handle_answer_query),
        cap(<<"hecate-rag.rerank_results">>,         handle_rerank_results),
        cap(<<"hecate-rag.get_chunk_by_id">>,        handle_get_chunk_by_id),
        cap(<<"hecate-rag.search_chunks_semantic">>, handle_search_chunks_semantic),
        cap(<<"hecate-rag.list_chunks_by_source">>,  handle_list_chunks_by_source),
        cap(<<"hecate-rag.get_source_by_id">>,       handle_get_source_by_id),
        cap(<<"hecate-rag.list_sources_page">>,      handle_list_sources_page),
        cap(<<"hecate-rag.detect_corpus_change">>,   handle_detect_corpus_change),
        cap(<<"hecate-rag.schedule_reembed">>,       handle_schedule_reembed)
    ].

cap(Name, HandlerFun) ->
    #{name => Name, version => 1,
      handler => {hecate_om_simple_handler, {hecate_rag_mesh_rpc, HandlerFun}}}.

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

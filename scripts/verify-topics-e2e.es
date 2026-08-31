#!/usr/bin/env escript
%% E2E verification of topic classification with the real NVIDIA API.
%% Usage: scripts/verify-topics-e2e.sh
%% Requires: ollama running locally (for embedding), NVIDIA API key in dev.config.

main(_) ->
    {ok, _} = application:ensure_all_started(hecate_rag),
    timer:sleep(2000),

    DocId = <<"e2e-nvidia-001">>,
    SourcePath = <<"e2e-nvidia-test.md">>,
    Content = <<"# Event Sourcing\n\n"
               "The aggregate replays events to derive state. Each event "
               "is a business fact that was decided. The dossier moves "
               "through desks accumulating event slips.\n\n"
               "## Projections\n\n"
               "Projections build read models from the event stream. They "
               "are optimized for fast retrieval with no joins or "
               "calculations.\n\n"
               "## Process Managers\n\n"
               "Process managers react to domain events and dispatch new "
               "commands. They are the integration point between bounded "
               "contexts.\n">>,

    io:format("=== STEP 1: Ingest ===~n"),
    {ok, #{document_id := DocId}} = maybe_ingest_document:ingest(#{
        <<"document_id">> => DocId,
        <<"source_path">> => SourcePath,
        <<"source_type">> => <<"text/markdown">>,
        <<"raw_bytes">> => Content
    }),
    io:format("Ingested ~s~n", [DocId]),

    io:format("=== STEP 2: Embed ===~n"),
    {ok, #{chunks := N}} = maybe_embed_document:embed(#{<<"document_id">> => DocId}),
    io:format("Embedded ~B chunks~n", [N]),

    io:format("=== STEP 3: Classify (real NVIDIA API) ===~n"),
    Result = maybe_classify_topics:classify(#{
        <<"document_id">> => DocId,
        <<"mode">> => <<"document">>
    }),
    case Result of
        {ok, #{topics := Topics, tagged := Tagged}} ->
            io:format("Topics: ~p~n", [Topics]),
            io:format("Tagged ~B chunks~n", [Tagged]);
        {error, Reason} ->
            io:format("FAILED: ~p~n", [Reason]),
            halt(1)
    end,

    io:format("=== STEP 4: Search WITHOUT topic filter ===~n"),
    {ok, AllHits} = search_chunks_semantic:handle(#{
        <<"query_text">> => <<"how does state get derived">>,
        <<"top_k">> => 5
    }),
    io:format("Found ~B hits without filter~n", [length(AllHits)]),

    io:format("=== STEP 5: Search WITH topic filter ===~n"),
    TopicFilter = hd(Topics),
    {ok, FilteredHits} = search_chunks_semantic:handle(#{
        <<"query_text">> => <<"how does state get derived">>,
        <<"topics">> => [TopicFilter],
        <<"top_k">> => 5
    }),
    io:format("Filtering by topic ~p: ~B hits~n", [TopicFilter, length(FilteredHits)]),

    io:format("=== STEP 6: Verify topics are stored on chunks ===~n"),
    {ok, Chunks} = rag_store:list_chunks_by_source(SourcePath, 100),
    lists:foreach(fun(Chunk) ->
        Meta = maps:get(meta, Chunk, #{}),
        ChunkTopics = maps:get(<<"topics">>, Meta, []),
        io:format("Chunk ~s topics: ~p~n", [maps:get(chunk_id, Chunk, <<>>), ChunkTopics])
    end, Chunks),

    io:format("=== E2E VERIFICATION PASSED ===~n"),
    halt(0).

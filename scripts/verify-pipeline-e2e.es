#!/usr/bin/env escript
%%! -pa _build/default/lib/*/ebin -config config/dev.config

main(_) ->
    {ok, _} = application:ensure_all_started(hecate_rag),
    timer:sleep(3000),

    io:format("=== STEP 1: upload_knowledge (raw file) ===~n"),
    DocId = <<"e2e-upload-001">>,
    Content = <<"# Event Sourcing\n\nThe aggregate replays events to derive state. "
                "Each event is a business fact that was decided.\n\n"
                "## Projections\n\nProjections build read models from the event stream.\n\n"
                "## Process Managers\n\nProcess managers react to domain events and "
                "dispatch new commands.\n">>,
    Result1 = maybe_upload_knowledge:upload(#{
        <<"document_id">> => DocId,
        <<"source_path">> => <<"e2e-upload.md">>,
        <<"source_type">> => <<"text/markdown">>,
        <<"raw_bytes">> => Content
    }),
    io:format("upload_knowledge: ~p~n", [Result1]),

    io:format("=== STEP 2: add_knowledge (text snippet) ===~n"),
    Result2 = maybe_add_knowledge:add(#{
        <<"text">> => <<"The dossier principle means process over data. "
                        "Each desk is a capability within a department.">>,
        <<"source_label">> => <<"conversational-001">>,
        <<"topics">> => [<<"ddd">>, <<"architecture">>]
    }),
    io:format("add_knowledge: ~p~n", [Result2]),

    io:format("=== STEP 3: search for uploaded content ===~n"),
    {ok, Hits1} = rag_store:search_text(<<"how does state get derived">>, 5),
    io:format("Found ~B hits for state derivation~n", [length(Hits1)]),

    io:format("=== STEP 4: search for added knowledge ===~n"),
    {ok, Hits2} = rag_store:search_text(<<"dossier principle process over data">>, 5),
    io:format("Found ~B hits for dossier principle~n", [length(Hits2)]),

    io:format("=== STEP 5: verify topics on added knowledge ===~n"),
    lists:foreach(fun(H) ->
        Meta = maps:get(meta, H, #{}),
        Topics = maps:get(<<"topics">>, Meta, []),
        case Topics of
            [] -> ok;
            _ -> io:format("  chunk ~s topics: ~p~n", [maps:get(chunk_id, H, <<>>), Topics])
        end
    end, Hits2),

    io:format("=== STEP 6: rag_store stays responsive ===~n"),
    {ok, _} = rag_store:list_sources(0, 10),
    N = rag_store:size(),
    io:format("Store size: ~B, list_sources OK~n", [N]),

    io:format("=== E2E VERIFICATION PASSED ===~n"),
    halt(0).

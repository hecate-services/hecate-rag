%% Smoke test: boot hecate-rag, seed agents corpus, run a handful of
%% queries directly through the slice handlers and through HTTP.
%%
%% Run inside the project root:
%%   cat scripts/smoke-seed-and-query.escript | \
%%     rebar3 shell --config config/dev.config --apps hecate_rag
%%
%% Requires:
%%   - ollama running with nomic-embed-text pulled
%%   - hecate-corpus cloned at ~/work/codeberg.org/hecate-social/hecate-corpus
timer:sleep(3000),

CorpusRoot = <<"/home/rl/work/codeberg.org/hecate-social/hecate-corpus/philosophy">>,

io:format("[1/4] seeding ~ts ...~n", [CorpusRoot]),
{ok, Stats} = maybe_seed_corpus:seed(#{
    <<"seed_id">>       => <<"agents-philosophy-v1">>,
    <<"root_dir">>      => CorpusRoot,
    <<"glob">>          => <<"**/*.md">>,
    <<"exclude_globs">> => []
}),
io:format("    stats: ~p~n", [Stats]),
io:format("    rag_store size: ~p~n", [rag_store:size()]),

io:format("~n[2/4] direct handler queries:~n"),
Show = fun(H) ->
    Meta   = maps:get(meta, H, #{}),
    Header = maps:get(<<"header_path">>, Meta, <<"">>),
    Src    = maps:get(source_path, H, <<"?">>),
    Score  = maps:get(score, H, 0.0),
    io:format("    ~.4f  ~ts :: ~ts~n", [Score, Src, Header])
end,
RunQ = fun(Text) ->
    io:format("  Q: ~ts~n", [Text]),
    case search_chunks_semantic:handle(#{<<"query_text">> => Text, <<"top_k">> => 3}) of
        {ok, []}   -> io:format("    (no hits)~n");
        {ok, Hits} -> lists:foreach(Show, Hits);
        Other      -> io:format("    ERR=~p~n", [Other])
    end
end,
RunQ(<<"what is the dossier principle">>),
RunQ(<<"why vertical slicing instead of horizontal layers">>),
RunQ(<<"how do process managers connect domains">>),

io:format("~n[3/4] HTTP /health:~n"),
inets:start(),
{ok, {{_, HC, _}, _, HB}} = httpc:request("http://127.0.0.1:8470/health"),
io:format("    HTTP ~p: ~ts~n", [HC, HB]),

io:format("~n[4/4] HTTP /api/rag/chunks/search (POST):~n"),
Body = iolist_to_binary(json:encode(#{<<"query_text">> => <<"dossier principle">>, <<"top_k">> => 3})),
case httpc:request(post,
                   {"http://127.0.0.1:8470/api/rag/chunks/search", [],
                    "application/json", Body},
                   [], [{body_format, binary}]) of
    {ok, {{_, 200, _}, _, SB}} ->
        Items = maps:get(<<"items">>, json:decode(SB), []),
        io:format("    HTTP 200, ~p items~n", [length(Items)]),
        lists:foreach(
            fun(H) ->
                io:format("    ~.4f  ~ts~n",
                          [maps:get(<<"score">>, H, 0.0),
                           maps:get(<<"source_path">>, H, <<"?">>)])
            end,
            Items);
    {ok, {{_, Code, _}, _, _}} ->
        io:format("    HTTP ~p (route not registered?)~n", [Code]);
    {error, Reason} ->
        io:format("    error: ~p~n", [Reason])
end,

io:format("~ndone.~n"),
halt().

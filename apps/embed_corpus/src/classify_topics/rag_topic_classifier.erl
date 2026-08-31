%%% @doc LLM-backed topic classifier.
%%%
%%% Calls an OpenAI-compatible chat completion API (NVIDIA NIM by
%%% default) to classify text into 1-N topic labels. Returns a list of
%%% binary topic strings.
%%%
%%% Config (under the `hecate_rag' app env):
%%%
%%%   {topic_classifier, #{
%%%       enabled  => true | false,       %% default false
%%%       api_key  => <<"nvapi-...">>,   %% required when enabled
%%%       endpoint => <<"https://integrate.api.nvidia.com/v1/chat/completions">>,
%%%       model    => <<"minimaxai/minimax-m3">>,
%%%       timeout  => 30000               %% ms
%%%   }}
%%%
%%% The API is OpenAI-compatible: POST a chat completion, receive
%%% `choices[0].message.content' containing a JSON array (possibly
%%% wrapped in a markdown code block — stripped defensively).
%%%
%%% Uses `httpc' (Erlang/OTP built-in) — no external HTTP dependency.
-module(rag_topic_classifier).

-export([classify/2, classify_batch/2, configured/0, extract_topics/1]).

-define(DEFAULT_ENDPOINT, <<"https://integrate.api.nvidia.com/v1/chat/completions">>).
-define(DEFAULT_MODEL,    <<"minimaxai/minimax-m3">>).
-define(DEFAULT_TIMEOUT,  30000).
-define(DEFAULT_MAX_TOPICS, 5).

-define(PROMPT_TEMPLATE,
    <<"Classify this text into 1-~B topic labels. "
      "Return ONLY a JSON array of lowercase string labels, nothing else. "
      "Be specific and concise (1-3 words per label).~n~nText: ~ts">>).

-type topic() :: binary().

%%% API

-spec configured() -> boolean().
configured() ->
    Config = topic_config(),
    maps:get(enabled, Config, false) =:= true andalso
    maps:get(api_key, Config, <<>>) =/= <<>>.

-spec classify(binary(), pos_integer()) -> {ok, [topic()]} | {error, term()}.
classify(Text, MaxTopics) when is_binary(Text), is_integer(MaxTopics), MaxTopics > 0 ->
    case configured() of
        false -> {error, classifier_not_configured};
        true  -> do_classify(Text, MaxTopics)
    end.

-spec classify_batch([binary()], pos_integer()) -> {ok, [[topic()]]} | {error, term()}.
classify_batch(Texts, MaxTopics) when is_list(Texts) ->
    Results = lists:foldl(fun(Text, {Ok, Err}) ->
        batch_one(Text, MaxTopics, Ok, Err)
    end, {[], []}, Texts),
    batch_result(Results).

%%% Internal — batch

batch_one(Text, MaxTopics, Ok, Err) ->
    case classify(Text, MaxTopics) of
        {ok, Topics} -> {[{Text, Topics} | Ok], Err};
        {error, R}   -> {Ok, [{Text, R} | Err]}
    end.

batch_result({Ok, Err}) ->
    case {Ok, Err} of
        {[], [_ | _]} -> {error, {all_failed, Err}};
        _             -> {ok, [Topics || {_Text, Topics} <- lists:reverse(Ok)]}
    end.

%%% Internal — classify

do_classify(Text, MaxTopics) ->
    ensure_http_apps(),
    Config = topic_config(),
    Prompt = build_prompt(Text, MaxTopics),
    Body = jsx:encode(#{
        <<"model">>       => maps:get(model, Config, ?DEFAULT_MODEL),
        <<"messages">>    => [
            #{<<"role">> => <<"user">>, <<"content">> => Prompt}
        ],
        <<"max_tokens">>  => 200,
        <<"temperature">> => 0
    }),
    Endpoint = binary_to_list(maps:get(endpoint, Config, ?DEFAULT_ENDPOINT)),
    Timeout  = maps:get(timeout, Config, ?DEFAULT_TIMEOUT),
    ApiKey   = binary_to_list(maps:get(api_key, Config, <<>>)),
    Headers  = [{"Content-Type", "application/json"},
                {"Authorization", "Bearer " ++ ApiKey}],
    case httpc:request(post, {Endpoint, Headers, "application/json", Body},
                       [{timeout, Timeout}], []) of
        {ok, {{_, 200, _}, _RespHeaders, RespBody}} ->
            parse_response(list_to_binary(RespBody));
        {ok, {{_, Status, _}, _RespHeaders, RespBody}} ->
            {error, {api_error, Status, RespBody}};
        {error, _} = E ->
            E
    end.

ensure_http_apps() ->
    {ok, _} = application:ensure_all_started(inets),
    {ok, _} = application:ensure_all_started(ssl),
    ok.

build_prompt(Text, MaxTopics) ->
    iolist_to_binary(io_lib:format(?PROMPT_TEMPLATE, [MaxTopics, Text])).

parse_response(RespBody) ->
    try
        #{<<"choices">> := [#{<<"message">> := #{<<"content">> := Content}} | _]} =
            jsx:decode(RespBody, [return_maps]),
        {ok, extract_topics(Content)}
    catch
        _:_ -> {error, invalid_response}
    end.

extract_topics(Content) when is_binary(Content) ->
    JsonArray = strip_code_fence(Content),
    decode_topics(JsonArray).

decode_topics(JsonArray) ->
    case catch jsx:decode(JsonArray, [return_maps]) of
        Topics when is_list(Topics) ->
            [to_topic(T) || T <- Topics, is_valid_topic(T)];
        _ ->
            []
    end.

strip_code_fence(Bin) ->
    case binary:split(Bin, <<"```">>) of
        [_, Middle | _] -> strip_inner_fence(Middle);
        _               -> Bin
    end.

strip_inner_fence(Middle) ->
    case binary:split(Middle, <<"```">>) of
        [Inner | _] -> strip_lang_prefix(Inner);
        _           -> Middle
    end.

strip_lang_prefix(Bin) ->
    case binary:split(Bin, <<"\n">>) of
        [Line, Rest] when Line =:= <<"json">>; Line =:= <<"JSON">> -> Rest;
        _ -> Bin
    end.

to_topic(T) when is_binary(T) -> string:lowercase(string:trim(T));
to_topic(T) when is_list(T)   -> to_topic(list_to_binary(T)).

is_valid_topic(T) when is_binary(T) -> byte_size(T) > 0;
is_valid_topic(T) when is_list(T)   -> length(T) > 0;
is_valid_topic(_)                   -> false.

topic_config() ->
    application:get_env(hecate_rag, topic_classifier, #{}).

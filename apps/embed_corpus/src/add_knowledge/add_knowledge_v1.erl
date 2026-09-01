%%% @doc Parameters for `add_knowledge'.
%%%
%%% Accepts a text snippet + optional metadata (source_label, topics).
%%% Designed for conversational deposits: an agent learns something
%%% during a session and pushes it directly. The server may chunk if
%%% the text is long, but the common case is a paragraph or two —
%%% one chunk, one embed, one store.
%%%
%%% Not an evoq command: same rationale as `ingest_document'.
-module(add_knowledge_v1).

-export([new/1, from_map/1, validate/1]).
-export([get_text/1, get_source_label/1, get_topics/1]).

-record(add_knowledge_v1, {
    text         :: binary() | undefined,
    source_label :: binary() | undefined,
    topics       :: [binary()] | undefined
}).

-opaque t() :: #add_knowledge_v1{}.
-export_type([t/0]).

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{text := Text} = Params) ->
    {ok, #add_knowledge_v1{
        text         = Text,
        source_label = maps:get(source_label, Params, undefined),
        topics       = maps:get(topics, Params, undefined)
    }};
new(_) ->
    {error, missing_text}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"text">> := Text} = Map) ->
    {ok, #add_knowledge_v1{
        text         = Text,
        source_label = maps:get(<<"source_label">>, Map, undefined),
        topics       = maps:get(<<"topics">>, Map, undefined)
    }};
from_map(_) ->
    {error, missing_text}.

-spec validate(t()) -> ok | {error, term()}.
validate(#add_knowledge_v1{text = undefined}) -> {error, missing_text};
validate(#add_knowledge_v1{text = <<>>}) -> {error, empty_text};
validate(_) -> ok.

-spec get_text(t()) -> binary() | undefined.
get_text(#add_knowledge_v1{text = V}) -> V.

-spec get_source_label(t()) -> binary() | undefined.
get_source_label(#add_knowledge_v1{source_label = V}) -> V.

-spec get_topics(t()) -> [binary()] | undefined.
get_topics(#add_knowledge_v1{topics = V}) -> V.

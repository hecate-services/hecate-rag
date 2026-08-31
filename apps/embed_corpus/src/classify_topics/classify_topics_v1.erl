%%% @doc Parameters for `classify_topics'.
%%%
%%% Classifies a document's chunks into 1-5 topic labels per chunk,
%%% using an LLM API (NVIDIA NIM by default). The document must already
%%% be embedded — `classify_topics' reads chunks back from `rag_store'
%%% by `document_id', classifies each chunk's content, and tags the
%%% stored chunk with the resulting topics.
%%%
%%% Not an evoq command: topic labels are a derived classification, not
%%% a business fact anyone decided. Same rationale as `embed_document'
%%% and `ingest_document' — see `embed_document_v1' for the full
%%% argument.
-module(classify_topics_v1).

-export([new/1, from_map/1, validate/1]).
-export([get_document_id/1, get_max_topics/1]).

-record(classify_topics_v1, {
    document_id :: binary() | undefined,
    max_topics  :: pos_integer() | undefined
}).

-opaque t() :: #classify_topics_v1{}.
-export_type([t/0]).

-define(DEFAULT_MAX_TOPICS, 5).

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{document_id := Id} = Params) ->
    {ok, #classify_topics_v1{
        document_id = Id,
        max_topics  = maps:get(max_topics, Params, ?DEFAULT_MAX_TOPICS)
    }};
new(_) ->
    {error, missing_document_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"document_id">> := Id} = Map) ->
    MaxTopics = case maps:get(<<"max_topics">>, Map, ?DEFAULT_MAX_TOPICS) of
        N when is_integer(N), N > 0 -> N;
        _                            -> ?DEFAULT_MAX_TOPICS
    end,
    {ok, #classify_topics_v1{document_id = Id, max_topics = MaxTopics}};
from_map(_) ->
    {error, missing_document_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#classify_topics_v1{document_id = undefined}) -> {error, missing_document_id};
validate(#classify_topics_v1{max_topics = N}) when N < 1 -> {error, invalid_max_topics};
validate(_) -> ok.

-spec get_document_id(t()) -> binary() | undefined.
get_document_id(#classify_topics_v1{document_id = V}) -> V.

-spec get_max_topics(t()) -> pos_integer().
get_max_topics(#classify_topics_v1{max_topics = V}) when is_integer(V), V > 0 -> V;
get_max_topics(_) -> ?DEFAULT_MAX_TOPICS.

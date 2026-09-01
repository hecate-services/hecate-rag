%%% @doc Parameters for `upload_knowledge'.
%%%
%%% Accepts a raw document (file bytes) + metadata. The handler chunks
%%% it via `markdown_chunker', embeds each chunk via `rag_embedder' (in
%%% a worker process, not inside `rag_store'), and writes each chunk
%%% with its vector to `rag_store'. The server owns chunking and
%%% embedding — the caller just sends raw content.
%%%
%%% Not an evoq command: same rationale as `ingest_document'.
-module(upload_knowledge_v1).

-export([new/1, from_map/1, validate/1]).
-export([get_document_id/1, get_source_path/1, get_source_type/1, get_raw_bytes/1]).

-record(upload_knowledge_v1, {
    document_id :: binary() | undefined,
    source_path :: binary() | undefined,
    source_type :: binary() | undefined,
    raw_bytes   :: binary() | undefined
}).

-opaque t() :: #upload_knowledge_v1{}.
-export_type([t/0]).

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{document_id := Id} = Params) ->
    {ok, #upload_knowledge_v1{
        document_id = Id,
        source_path = maps:get(source_path, Params, undefined),
        source_type = maps:get(source_type, Params, undefined),
        raw_bytes   = maps:get(raw_bytes, Params, undefined)
    }};
new(_) ->
    {error, missing_document_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"document_id">> := Id} = Map) ->
    {ok, #upload_knowledge_v1{
        document_id = Id,
        source_path = maps:get(<<"source_path">>, Map, undefined),
        source_type = maps:get(<<"source_type">>, Map, undefined),
        raw_bytes   = maps:get(<<"raw_bytes">>, Map, undefined)
    }};
from_map(_) ->
    {error, missing_document_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#upload_knowledge_v1{document_id = undefined}) -> {error, missing_document_id};
validate(#upload_knowledge_v1{raw_bytes = undefined}) -> {error, missing_raw_bytes};
validate(#upload_knowledge_v1{raw_bytes = <<>>}) -> {error, empty_content};
validate(_) -> ok.

-spec get_document_id(t()) -> binary() | undefined.
get_document_id(#upload_knowledge_v1{document_id = V}) -> V.

-spec get_source_path(t()) -> binary() | undefined.
get_source_path(#upload_knowledge_v1{source_path = V}) -> V.

-spec get_source_type(t()) -> binary() | undefined.
get_source_type(#upload_knowledge_v1{source_type = V}) -> V.

-spec get_raw_bytes(t()) -> binary() | undefined.
get_raw_bytes(#upload_knowledge_v1{raw_bytes = V}) -> V.

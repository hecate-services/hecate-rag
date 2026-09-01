%%% @doc Handler for `upload_knowledge': the full server-side pipeline.
%%%
%%% 1. Stores the source record (so the document is listable).
%%% 2. Chunks the raw content via `markdown_chunker' (fast, local).
%%% 3. Embeds each chunk via `rag_chunk_embedder' (in THIS process, not
%%%    inside `rag_store''s gen_server — the gen_server stays fast).
%%% 4. Writes each chunk + vector to `rag_store'.
%%%
%%% The caller sends raw bytes; the server owns chunking and embedding.
-module(maybe_upload_knowledge).

-export([upload/1]).

-define(MAX_CHUNK_CHARS, 2000).

-spec upload(map()) -> {ok, #{document_id := binary(), chunks := non_neg_integer()}} |
                        {error, term()}.
upload(Params) when is_map(Params) ->
    case upload_knowledge_v1:from_map(Params) of
        {ok, Cmd}      -> upload_cmd(Cmd);
        {error, _} = E -> E
    end.

upload_cmd(Cmd) ->
    case upload_knowledge_v1:validate(Cmd) of
        ok         -> do_upload(Cmd);
        {error, R} -> {error, R}
    end.

do_upload(Cmd) ->
    Id = upload_knowledge_v1:get_document_id(Cmd),
    SourcePath = upload_knowledge_v1:get_source_path(Cmd),
    SourceType = upload_knowledge_v1:get_source_type(Cmd),
    RawBytes = upload_knowledge_v1:get_raw_bytes(Cmd),
    Path = path_or_id(SourcePath, Id),
    ok = rag_store:upsert_source(#{
        document_id => Id,
        source_path => Path,
        source_type => SourceType,
        raw_bytes => RawBytes
    }),
    Chunks = markdown_chunker:chunk_text(RawBytes, Path, ?MAX_CHUNK_CHARS),
    {Stored, Errors} = rag_chunk_embedder:embed_and_store(Chunks),
    log_errors(Errors),
    {ok, #{document_id => Id, chunks => Stored}}.

log_errors([]) -> ok;
log_errors(Errors) ->
    lists:foreach(fun({ChunkId, Reason}) ->
        logger:warning("[upload_knowledge] chunk ~s failed: ~p", [ChunkId, Reason])
    end, Errors).

path_or_id(<<>>, Id) -> Id;
path_or_id(Path, _)   -> Path.

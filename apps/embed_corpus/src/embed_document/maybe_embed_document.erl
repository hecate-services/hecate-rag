%%% @doc Handler for `embed_document': chunks the raw content
%%% `ingest_document' recorded against this document (read back from
%%% `rag_store', not from the command — `embed_document' carries no raw
%%% content of its own, so a document can be re-embedded without
%%% resubmitting it) and writes each chunk to `rag_store'. Embedding
%%% happens automatically: `rag_store' opens its database in barrel
%%% "record mode", so `put_chunk/3' embeds `content' per the configured
%%% policy — there is no separate embed call to make here.
%%%
%%% Same header-aware chunker `seed_corpus' uses (`markdown_chunker'). This
%%% is the audit-worthy, per-document path; `seed_corpus' is the
%%% deliberate bulk bypass. Both land in the same `rag_store'.
-module(maybe_embed_document).

-export([embed/1]).

%% Matches `markdown_chunker:chunk_file/2''s own internal default — there is
%% exactly one chunk-size policy in this codebase, not two.
-define(MAX_CHUNK_CHARS, 2000).

-spec embed(map()) -> {ok, #{document_id := binary(), chunks := non_neg_integer()}} |
                       {error, term()}.
embed(Params) when is_map(Params) ->
    case embed_document_v1:from_map(Params) of
        {ok, Cmd}      -> embed_cmd(Cmd);
        {error, _} = E -> E
    end.

embed_cmd(Cmd) ->
    case embed_document_v1:validate(Cmd) of
        ok         -> do_embed(Cmd);
        {error, R} -> {error, R}
    end.

do_embed(Cmd) ->
    Id = embed_document_v1:get_document_id(Cmd),
    case rag_store:get_source_content(Id) of
        {ok, Content} -> chunk_and_store(Id, Content);
        {error, not_found} -> {error, not_ingested}
    end.

chunk_and_store(Id, #{source_path := SourcePath, raw_bytes := RawBytes}) ->
    Path = source_path_or_id(SourcePath, Id),
    Chunks = markdown_chunker:chunk_text(RawBytes, Path, ?MAX_CHUNK_CHARS),
    case put_all(Chunks) of
        ok             -> {ok, #{document_id => Id, chunks => length(Chunks)}};
        {error, _} = E -> E
    end.

%% First error stops the batch; chunks already written stay written (each
%% `put_chunk' is its own atomic barrel write, there is no larger
%% transaction to roll back, and a partial embed is safe to retry — every
%% chunk id is content-derived, so re-running just re-writes the same ids).
put_all(Chunks) ->
    put_all(Chunks, ok).

put_all([], Result) ->
    Result;
put_all(_Chunks, {error, _} = E) ->
    E;
put_all([Chunk | Rest], ok) ->
    put_all(Rest, put_one(Chunk)).

put_one(#{chunk_id := ChunkId, content := Content} = Chunk) ->
    Meta = maps:without([chunk_id, content], Chunk),
    rag_store:put_chunk(ChunkId, Content, Meta).

%% `markdown_chunker' only uses this to stamp `source_path' on each chunk;
%% fall back to the document id so a document ingested without one still
%% gets a stable, non-empty tag.
source_path_or_id(<<>>, Id)  -> Id;
source_path_or_id(Path, _Id) -> Path.

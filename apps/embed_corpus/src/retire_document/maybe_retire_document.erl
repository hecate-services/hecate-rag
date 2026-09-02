%%% @doc Handler for `retire_document': a document leaves the corpus
%%% entirely -- every chunk recorded against its `source_path' (through
%%% `maybe_prune_chunks', the one prune implementation) AND the source
%%% record `ingest_document'/`seed_corpus'/the corpus git loop wrote.
%%% Afterwards `get_source_by_id', `list_sources_page' and
%%% `get_document_verbatim' no longer know the document, and semantic
%%% search no longer hits it.
%%%
%%% `prune_chunks' deliberately keeps the source record (a re-embed
%%% needs it to chunk from). This desk is for the other case: the
%%% document is gone for good. First use (2026-09-02): the bare-path
%%% duplicates a months-old manual seed left on beam03 before document
%%% ids were repo-namespaced -- `README.md' beside
%%% `hecate-corpus/README.md'.
%%%
%%% Not event-sourced, for the same reason as `embed_document_v1'.
-module(maybe_retire_document).

-export([retire/1]).

-spec retire(map()) -> {ok, #{document_id := binary(), pruned := non_neg_integer()}} |
                        {error, term()}.
retire(Params) when is_map(Params) ->
    case retire_document_v1:from_map(Params) of
        {ok, Cmd}      -> retire_cmd(Cmd);
        {error, _} = E -> E
    end.

retire_cmd(Cmd) ->
    case retire_document_v1:validate(Cmd) of
        ok         -> do_retire(retire_document_v1:get_document_id(Cmd));
        {error, R} -> {error, R}
    end.

%% Chunks first, then the source record: a failure in between leaves a
%% chunk-less source (harmless, and re-runnable), never orphan chunks
%% that no listing can reach any more.
do_retire(Id) ->
    chunks_pruned(maybe_prune_chunks:prune(#{<<"document_id">> => Id}), Id).

chunks_pruned({ok, #{pruned := Pruned}}, Id) ->
    source_forgotten(rag_store:forget_source(Id), Id, length(Pruned));
chunks_pruned({error, _} = E, _Id) ->
    E.

source_forgotten(ok, Id, Pruned)          -> {ok, #{document_id => Id, pruned => Pruned}};
source_forgotten({error, _} = E, _Id, _N) -> E.

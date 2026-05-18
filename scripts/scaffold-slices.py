#!/usr/bin/env python3
"""Regenerate vertical-slice stub files for hecate-rag.

Run from anywhere:

    python3 scripts/scaffold-slices.py

Writes:
  apps/<cmd_app>/src/<cmd_app>.app.src
  apps/<cmd_app>/src/<cmd_app>_app.erl
  apps/<cmd_app>/src/<cmd_app>_sup.erl
  apps/<cmd_app>/src/<slice>/<slice>_v1.erl
  apps/<cmd_app>/src/<slice>/<event>_v1.erl
  apps/<cmd_app>/src/<slice>/maybe_<slice>.erl
  apps/<cmd_app>/src/<slice>/<slice>_api.erl

  apps/<qry_app>/src/<qry_app>.app.src
  apps/<qry_app>/src/<qry_app>_app.erl
  apps/<qry_app>/src/<qry_app>_sup.erl
  apps/<qry_app>/src/<desk>/<desk>.erl
  apps/<qry_app>/src/<desk>/<desk>_api.erl

  apps/<prj_app>/src/<prj_app>.app.src
  apps/<prj_app>/src/<prj_app>_app.erl
  apps/<prj_app>/src/<prj_app>_sup.erl
  apps/<prj_app>/src/<event>_to_<table>.erl

Idempotent: rerunning overwrites generated files; non-generated entry
points (umbrella root) live outside this script.
"""
from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPS = ROOT / "apps"

# ---------------------------------------------------------------- model

CMD_APPS = {
    "embed_corpus": {
        "description": "Embed corpus documents into vectors (CMD)",
        "slices": [
            {
                "slice":     "ingest_document",
                "event":     "document_ingested",
                "aggregate": "document",
                "fields":    ["source_path", "source_type", "raw_bytes"],
                "http":      ("POST", "/api/rag/documents/ingest"),
            },
            {
                "slice":     "embed_document",
                "event":     "document_embedded",
                "aggregate": "document",
                "fields":    ["chunks", "model_id", "dim"],
                "http":      ("POST", "/api/rag/documents/embed"),
            },
            {
                "slice":     "prune_chunks",
                "event":     "chunks_pruned",
                "aggregate": "document",
                "fields":    ["chunk_ids", "reason"],
                "http":      ("POST", "/api/rag/documents/prune"),
            },
        ],
    },
    "refresh_corpus": {
        "description": "Detect corpus changes and schedule re-embed (CMD)",
        "slices": [
            {
                "slice":     "detect_corpus_change",
                "event":     "corpus_change_detected",
                "aggregate": "corpus",
                "fields":    ["source_path", "kind", "diff_hash"],
                "http":      ("POST", "/api/rag/corpus/changes/detect"),
            },
            {
                "slice":     "schedule_reembed",
                "event":     "reembed_scheduled",
                "aggregate": "corpus",
                "fields":    ["source_path", "priority", "scheduled_at"],
                "http":      ("POST", "/api/rag/corpus/reembed/schedule"),
            },
        ],
    },
    "serve_retrieval": {
        "description": "Answer retrieval queries from the index (CMD)",
        "slices": [
            {
                "slice":     "answer_query",
                "event":     "query_answered",
                "aggregate": "query",
                "fields":    ["query_text", "top_k", "filters", "hits"],
                "http":      ("POST", "/api/rag/queries/answer"),
            },
            {
                "slice":     "rerank_results",
                "event":     "results_reranked",
                "aggregate": "query",
                "fields":    ["original_ranking", "reranker_model"],
                "http":      ("POST", "/api/rag/queries/rerank"),
            },
        ],
    },
}

QRY_APPS = {
    "query_chunks": {
        "description": "Chunk read model (chunk text + vector ref + metadata) (QRY)",
        "desks": [
            {"desk": "get_chunk_by_id",       "kind": "byid", "http": ("GET", "/api/rag/chunks/:chunk_id")},
            {"desk": "search_chunks_semantic","kind": "page", "http": ("GET", "/api/rag/chunks/search")},
            {"desk": "list_chunks_by_source", "kind": "page", "http": ("GET", "/api/rag/chunks/by-source")},
        ],
    },
    "query_sources": {
        "description": "Source read model (per-document metadata) (QRY)",
        "desks": [
            {"desk": "get_source_by_id",  "kind": "byid", "http": ("GET", "/api/rag/sources/:source_id")},
            {"desk": "list_sources_page", "kind": "page", "http": ("GET", "/api/rag/sources")},
        ],
    },
}

PRJ_APPS = {
    "project_chunks": {
        "description": "Project chunk-relevant events into the chunks read model (PRJ)",
        "projections": [
            {"event": "document_embedded_v1", "table": "chunks", "source_app": "embed_corpus"},
            {"event": "chunks_pruned_v1",     "table": "chunks", "source_app": "embed_corpus"},
        ],
    },
    "project_sources": {
        "description": "Project source-relevant events into the sources read model (PRJ)",
        "projections": [
            {"event": "document_ingested_v1", "table": "sources", "source_app": "embed_corpus"},
        ],
    },
}

# --------------------------------------------------------------- helpers

def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    rel = path.relative_to(ROOT)
    print(f"  wrote {rel}")

def app_src(app: str, deps: list[str], desc: str, has_app_mod: bool = True) -> str:
    deps_str = ",\n        ".join(deps)
    mod_line = "    {mod, {%s_app, []}},\n" % app if has_app_mod else ""
    return f"""{{application, {app}, [
    {{description, "{desc}"}},
    {{vsn, "0.1.0"}},
    {{registered, []}},
{mod_line}    {{applications, [
        {deps_str}
    ]}},
    {{env, []}},
    {{modules, []}},
    {{licenses, ["Apache-2.0"]}}
]}}.
"""

def app_mod(app: str) -> str:
    return f"""-module({app}_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    {app}_sup:start_link().

stop(_State) ->
    ok.
"""

def sup_mod(app: str, children: str = "[]") -> str:
    return f"""-module({app}_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({{local, ?MODULE}}, ?MODULE, []).

init([]) ->
    {{ok, {{
        #{{strategy => one_for_one, intensity => 10, period => 10}},
        {children}
    }}}}.
"""

def cmd_v1(slice: str, fields: list[str], aggregate: str) -> str:
    record_fields = ",\n    ".join([f"{f} :: binary() | undefined" for f in [f"{aggregate}_id"] + fields])
    setters = "\n".join([f"-spec get_{f}(t()) -> binary() | undefined.\nget_{f}(#{slice}_v1{{{f} = V}}) -> V.\n" for f in [f"{aggregate}_id"] + fields])
    map_pairs = ",\n        ".join([f"{f} => Cmd#{slice}_v1.{f}" for f in [f"{aggregate}_id"] + fields])
    return f"""%%% @doc Command `{slice}_v1`.
%%%
%%% Generated stub. Add validation in `maybe_{slice}` once the slice
%%% has real business rules.
-module({slice}_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([{", ".join(['get_' + f + '/1' for f in [f'{aggregate}_id'] + fields])}]).

-record({slice}_v1, {{
    {record_fields}
}}).

-opaque t() :: #{slice}_v1{{}}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> {slice}_v1.

-spec new(map()) -> {{ok, t()}} | {{error, term()}}.
new(#{{{aggregate}_id := Id}} = Params) ->
    {{ok, #{slice}_v1{{
        {aggregate}_id = Id{("," if fields else "")}
        {",\n        ".join([f"{f} = maps:get({f}, Params, undefined)" for f in fields])}
    }}}};
new(_) ->
    {{error, missing_aggregate_id}}.

-spec from_map(map()) -> {{ok, t()}} | {{error, term()}}.
from_map(#{{<<"{aggregate}_id">> := Id}} = Map) ->
    {{ok, #{slice}_v1{{
        {aggregate}_id = Id{("," if fields else "")}
        {",\n        ".join([f'{f} = maps:get(<<"{f}">>, Map, undefined)' for f in fields])}
    }}}};
from_map(_) ->
    {{error, missing_aggregate_id}}.

-spec validate(t()) -> ok | {{error, term()}}.
validate(#{slice}_v1{{{aggregate}_id = undefined}}) -> {{error, missing_aggregate_id}};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#{slice}_v1{{}} = Cmd) ->
    #{{
        command_type => {slice}_v1,
        {map_pairs}
    }}.

-spec stream_id(t()) -> binary().
stream_id(#{slice}_v1{{{aggregate}_id = Id}}) ->
    <<"{aggregate}-", Id/binary>>.

{setters}"""

def event_v1(event: str, fields: list[str], aggregate: str) -> str:
    record_fields = ",\n    ".join([f"{f} :: binary() | undefined" for f in [f"{aggregate}_id"] + fields])
    setters = "\n".join([f"get_{f}(#{event}_v1{{{f} = V}}) -> V." for f in [f"{aggregate}_id"] + fields])
    map_pairs = ",\n        ".join([f"{f} => Ev#{event}_v1.{f}" for f in [f"{aggregate}_id"] + fields])
    return f"""%%% @doc Event `{event}_v1`.
-module({event}_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([{", ".join(['get_' + f + '/1' for f in [f'{aggregate}_id'] + fields])}]).

-record({event}_v1, {{
    {record_fields}
}}).

-opaque t() :: #{event}_v1{{}}.
-export_type([t/0]).

event_type() -> {event}_v1.

-spec new(map()) -> {{ok, t()}}.
new(#{{{aggregate}_id := Id}} = Params) ->
    {{ok, #{event}_v1{{
        {aggregate}_id = Id{("," if fields else "")}
        {",\n        ".join([f"{f} = maps:get({f}, Params, undefined)" for f in fields])}
    }}}}.

-spec from_map(map()) -> {{ok, t()}}.
from_map(#{{<<"{aggregate}_id">> := Id}} = Map) ->
    {{ok, #{event}_v1{{
        {aggregate}_id = Id{("," if fields else "")}
        {",\n        ".join([f'{f} = maps:get(<<"{f}">>, Map, undefined)' for f in fields])}
    }}}}.

-spec to_map(t()) -> map().
to_map(#{event}_v1{{}} = Ev) ->
    #{{
        event_type => {event}_v1,
        {map_pairs}
    }}.

{setters}
"""

def handler_mod(slice: str, event: str, aggregate: str) -> str:
    return f"""%%% @doc Handler for `{slice}_v1`. Validates the command and produces
%%% `{event}_v1` as its outcome. Wire into evoq via
%%% `evoq:register_handler({slice}_v1, ?MODULE)` once business rules
%%% land here.
-module(maybe_{slice}).

-export([handle/1, handle/2, dispatch/1]).

-spec handle({slice}_v1:t()) ->
    {{ok, [{event}_v1:t()]}} | {{error, term()}}.
handle(Cmd) -> handle(Cmd, undefined).

-spec handle({slice}_v1:t(), term()) ->
    {{ok, [{event}_v1:t()]}} | {{error, term()}}.
handle(Cmd, _State) ->
    case {slice}_v1:validate(Cmd) of
        ok ->
            {{ok, Event}} = {event}_v1:new(#{{
                {aggregate}_id => {slice}_v1:get_{aggregate}_id(Cmd)
                %% TODO: copy relevant fields from Cmd into Event
            }}),
            {{ok, [Event]}};
        {{error, R}} ->
            {{error, R}}
    end.

%% @doc Dispatch via evoq — persists the produced event(s).
-spec dispatch({slice}_v1:t()) -> ok | {{error, term()}}.
dispatch(Cmd) ->
    StreamId = {slice}_v1:stream_id(Cmd),
    evoq:dispatch(rag_store, StreamId, Cmd, ?MODULE).
"""

def api_mod(slice: str, http_method: str, http_path: str) -> str:
    method_atom = http_method.upper()
    return f"""%%% @doc Cowboy handler — {http_method} {http_path}.
-module({slice}_api).

-export([init/2, routes/0]).

routes() -> [{{"{http_path}", ?MODULE, []}}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"{method_atom}">> -> handle(Req0, State);
        _                  -> hecate_rag_http:method_not_allowed(Req0)
    end.

handle(Req0, _State) ->
    case hecate_rag_http:read_json_body(Req0) of
        {{ok, Params, Req1}} ->
            case {slice}_v1:from_map(Params) of
                {{ok, Cmd}} ->
                    case maybe_{slice}:dispatch(Cmd) of
                        ok ->
                            hecate_rag_http:ok_json(#{{status => accepted}}, Req1);
                        {{error, Reason}} ->
                            hecate_rag_http:bad_request(reason_to_bin(Reason), Req1)
                    end;
                {{error, Reason}} ->
                    hecate_rag_http:bad_request(reason_to_bin(Reason), Req1)
            end;
        {{error, invalid_json, Req1}} ->
            hecate_rag_http:bad_request(<<"Invalid JSON">>, Req1)
    end.

reason_to_bin(R) when is_atom(R)   -> atom_to_binary(R, utf8);
reason_to_bin(R) when is_binary(R) -> R;
reason_to_bin(R)                   -> iolist_to_binary(io_lib:format("~p", [R])).
"""

def projection_mod(event: str, table: str, source_app: str) -> str:
    return f"""%%% @doc Projection: {event} → {table} read model.
%%%
%%% Subscribes to {event} via pg, writes to the SQLite `{table}` table.
-module({event}_to_{table}).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(PG_SCOPE, rag).
-define(EVENT_TOPIC, <<"{event}">>).

start_link() ->
    gen_server:start_link({{local, ?MODULE}}, ?MODULE, [], []).

init([]) ->
    pg:join(?PG_SCOPE, ?EVENT_TOPIC, self()),
    {{ok, #{{}}}}.

handle_call(_Msg, _From, State) -> {{reply, ok, State}}.
handle_cast(_Msg, State)         -> {{noreply, State}}.

handle_info({{evoq_event, Envelope}}, State) ->
    %% TODO: read event payload from Envelope, upsert into `{table}` table.
    %% Use esqlite via app_ragd_paths:sqlite_db/0.
    _ = Envelope,
    {{noreply, State}};
handle_info(_Other, State) ->
    {{noreply, State}}.

terminate(_Reason, _State) -> ok.
"""

def qry_byid_mod(desk: str, http_method: str, http_path: str) -> str:
    return f"""%%% @doc Query desk: {desk}. Looks up by id from the read model.
-module({desk}).

-export([handle/1]).

-spec handle(binary()) -> {{ok, map()}} | {{error, term()}}.
handle(_Id) ->
    %% TODO: SELECT from SQLite read model via esqlite.
    {{error, not_implemented}}.
"""

def qry_byid_api(desk: str, http_method: str, http_path: str) -> str:
    # Extract the binding name from the path pattern at generation time.
    binding = "id"
    for seg in http_path.split("/"):
        if seg.startswith(":"):
            binding = seg[1:]
            break
    return f"""%%% @doc Cowboy handler — {http_method} {http_path}.
-module({desk}_api).

-export([init/2, routes/0]).

routes() -> [{{"{http_path}", ?MODULE, []}}].

init(Req0, _State) ->
    case cowboy_req:method(Req0) of
        <<"{http_method.upper()}">> ->
            Id = cowboy_req:binding({binding}, Req0),
            case {desk}:handle(Id) of
                {{ok, Result}} ->
                    hecate_rag_http:ok_json(Result, Req0);
                {{error, not_found}} ->
                    hecate_rag_http:not_found(Req0);
                {{error, Reason}} ->
                    hecate_rag_http:bad_request(
                        iolist_to_binary(io_lib:format("~p", [Reason])), Req0)
            end;
        _ ->
            hecate_rag_http:method_not_allowed(Req0)
    end.
"""

def qry_page_mod(desk: str, http_method: str, http_path: str) -> str:
    return f"""%%% @doc Query desk: {desk}. Returns a page of results.
-module({desk}).

-export([handle/1]).

-spec handle(map()) -> {{ok, [map()]}} | {{error, term()}}.
handle(_Params) ->
    %% TODO: SELECT page from SQLite read model.
    {{ok, []}}.
"""

def qry_page_api(desk: str, http_method: str, http_path: str) -> str:
    return f"""%%% @doc Cowboy handler — {http_method} {http_path}.
-module({desk}_api).

-export([init/2, routes/0]).

routes() -> [{{"{http_path}", ?MODULE, []}}].

init(Req0, _State) ->
    case cowboy_req:method(Req0) of
        <<"{http_method.upper()}">> ->
            Params = maps:from_list(cowboy_req:parse_qs(Req0)),
            case {desk}:handle(Params) of
                {{ok, Items}} ->
                    hecate_rag_http:ok_json(#{{items => Items}}, Req0);
                {{error, Reason}} ->
                    hecate_rag_http:bad_request(
                        iolist_to_binary(io_lib:format("~p", [Reason])), Req0)
            end;
        _ ->
            hecate_rag_http:method_not_allowed(Req0)
    end.
"""

# -------------------------------------------------------------- run

def generate_cmd_apps():
    for app, cfg in CMD_APPS.items():
        deps = ["kernel", "stdlib", "crypto", "cowboy", "reckon_db", "evoq", "reckon_evoq", "rag"]
        write(APPS / app / "src" / f"{app}.app.src",
              app_src(app, deps, cfg["description"]))
        write(APPS / app / "src" / f"{app}_app.erl", app_mod(app))
        write(APPS / app / "src" / f"{app}_sup.erl", sup_mod(app))
        for sl in cfg["slices"]:
            slice = sl["slice"]
            event = sl["event"]
            agg   = sl["aggregate"]
            fields = sl["fields"]
            http_m, http_p = sl["http"]
            d = APPS / app / "src" / slice
            write(d / f"{slice}_v1.erl",      cmd_v1(slice, fields, agg))
            write(d / f"{event}_v1.erl",      event_v1(event, fields, agg))
            write(d / f"maybe_{slice}.erl",   handler_mod(slice, event, agg))
            write(d / f"{slice}_api.erl",     api_mod(slice, http_m, http_p))

def generate_qry_apps():
    for app, cfg in QRY_APPS.items():
        deps = ["kernel", "stdlib", "crypto", "cowboy", "esqlite", "rag"]
        write(APPS / app / "src" / f"{app}.app.src",
              app_src(app, deps, cfg["description"]))
        write(APPS / app / "src" / f"{app}_app.erl", app_mod(app))
        write(APPS / app / "src" / f"{app}_sup.erl", sup_mod(app))
        for d in cfg["desks"]:
            desk = d["desk"]
            kind = d["kind"]
            http_m, http_p = d["http"]
            folder = APPS / app / "src" / desk
            if kind == "byid":
                write(folder / f"{desk}.erl",     qry_byid_mod(desk, http_m, http_p))
                write(folder / f"{desk}_api.erl", qry_byid_api(desk, http_m, http_p))
            else:
                write(folder / f"{desk}.erl",     qry_page_mod(desk, http_m, http_p))
                write(folder / f"{desk}_api.erl", qry_page_api(desk, http_m, http_p))

def generate_prj_apps():
    for app, cfg in PRJ_APPS.items():
        deps = ["kernel", "stdlib", "crypto", "esqlite", "reckon_db", "evoq", "reckon_evoq", "rag"]
        children = ",\n        ".join([
            f"#{{id => {p['event']}_to_{p['table']}, "
            f"start => {{{p['event']}_to_{p['table']}, start_link, []}}, "
            f"restart => permanent, shutdown => 5000, type => worker, "
            f"modules => [{p['event']}_to_{p['table']}]}}"
            for p in cfg["projections"]
        ])
        write(APPS / app / "src" / f"{app}.app.src",
              app_src(app, deps, cfg["description"]))
        write(APPS / app / "src" / f"{app}_app.erl", app_mod(app))
        write(APPS / app / "src" / f"{app}_sup.erl", sup_mod(app, f"[{children}]"))
        for p in cfg["projections"]:
            write(APPS / app / "src" / f"{p['event']}_to_{p['table']}.erl",
                  projection_mod(p["event"], p["table"], p["source_app"]))

def main():
    print("Scaffolding hecate-rag vertical slices into:")
    print(f"  {APPS}")
    generate_cmd_apps()
    generate_qry_apps()
    generate_prj_apps()
    print("Done.")

if __name__ == "__main__":
    main()

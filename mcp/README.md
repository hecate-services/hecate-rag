# hecate-rag-mcp

Tiny stdio MCP server that bridges Claude (or any other MCP client) to
a local `hecate-rag` HTTP listener.

## Tools

| Tool | What |
|------|------|
| `hecate_rag_search` | semantic search over the indexed corpus, returns top-k chunks with citations |
| `hecate_rag_seed`   | bulk-ingest a markdown directory |

## Build

```
npm install
npm run build
```

Produces `dist/index.js` (the executable stdio server).

## Configure Claude

Add to `~/.claude/settings.json` (or your project `.mcp.json`):

```jsonc
{
  "mcpServers": {
    "hecate-rag": {
      "command": "node",
      "args": ["/home/rl/work/codeberg.org/hecate-services/hecate-rag/mcp/dist/index.js"],
      "env": {
        "HECATE_RAG_URL": "http://127.0.0.1:8470"
      }
    }
  }
}
```

Then in Claude Code: `/mcp` should list `hecate-rag` as connected and
its two tools as available.

## Run hecate-rag

In another terminal, run the dev container:

```
cd ../   # back to hecate-rag root
scripts/dev-up.sh
```

Seed the corpus once:

```
scripts/seed-corpus.sh /corpus agents-v1
```

After that, every `hecate_rag_search` call hits the live index.

## License

Apache-2.0.

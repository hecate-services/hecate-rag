#!/usr/bin/env node
/**
 * hecate-rag-mcp — MCP stdio bridge for hecate-rag.
 *
 * Exposes two tools to Claude:
 *
 *   - hecate_rag_search    semantic chunk search
 *   - hecate_rag_seed      bulk-ingest a markdown directory
 *
 * Talks to a local hecate-rag HTTP listener (default
 * http://127.0.0.1:8470). Override via HECATE_RAG_URL.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const BASE_URL = process.env.HECATE_RAG_URL ?? "http://127.0.0.1:8470";

interface SearchHit {
  chunk_id: string;
  content: string;
  source_path: string;
  score: number;
  meta?: Record<string, unknown>;
}

async function ragSearch(query: string, topK: number) {
  const res = await fetch(`${BASE_URL}/api/rag/chunks/search`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query_text: query, top_k: topK }),
  });
  if (!res.ok) {
    throw new Error(`hecate-rag search returned ${res.status}: ${await res.text()}`);
  }
  const json = (await res.json()) as { items: SearchHit[] };
  return json.items ?? [];
}

async function ragSeed(rootDir: string, seedId: string, glob: string, sync: boolean) {
  const res = await fetch(`${BASE_URL}/api/rag/seed`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      seed_id: seedId,
      root_dir: rootDir,
      glob,
      exclude_globs: ["_build/", "/priv/", "/assets/", "hecate-app-template/"],
      sync,
    }),
  });
  if (!res.ok) {
    throw new Error(`hecate-rag seed returned ${res.status}: ${await res.text()}`);
  }
  return res.json();
}

function formatHits(hits: SearchHit[]): string {
  if (hits.length === 0) return "(no hits)";
  return hits
    .map((h) => {
      const header =
        (h.meta as { header_path?: string } | undefined)?.header_path ?? "";
      const head = h.content.length > 600 ? h.content.slice(0, 600) + "…" : h.content;
      return `## ${h.source_path}  (score ${h.score.toFixed(4)})
**${header}**

${head}`;
    })
    .join("\n\n---\n\n");
}

const server = new Server(
  { name: "hecate-rag", version: "0.1.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "hecate_rag_search",
      description:
        "Search the indexed Hecate agents corpus (philosophy, guides, skills, antipatterns, naming, vertical slicing, dossier, venture lifecycle, ALC, etc.). Returns top-k chunks with citations. Use whenever a question is about Hecate architecture, naming, antipatterns, or conventions.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "The natural-language query." },
          top_k: {
            type: "integer",
            description: "How many chunks to return.",
            default: 5,
            minimum: 1,
            maximum: 20,
          },
        },
        required: ["query"],
      },
    },
    {
      name: "hecate_rag_seed",
      description:
        "Bulk-ingest a markdown directory into the RAG index. Walks all *.md files under `root_dir`, header-chunks them, embeds each chunk via the configured embedder, persists into rag_store. Re-runnable: same content + same path → same chunk_id (upsert).",
      inputSchema: {
        type: "object",
        properties: {
          root_dir: {
            type: "string",
            description:
              "Absolute path INSIDE the hecate-rag container. The dev container bind-mounts ~/work/codeberg.org/hecate-social/hecate-corpus at /corpus.",
          },
          seed_id: {
            type: "string",
            description: "Logical id for this seed run (any non-empty string).",
            default: "agents-v1",
          },
          glob: {
            type: "string",
            description: "Wildcard relative to root_dir.",
            default: "**/*.md",
          },
          sync: {
            type: "boolean",
            description: "Block until done. Use false for large corpora.",
            default: true,
          },
        },
        required: ["root_dir"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params;
  try {
    if (name === "hecate_rag_search") {
      const query = String(args?.query ?? "");
      const topK = Number(args?.top_k ?? 5);
      if (!query) throw new Error("`query` is required");
      const hits = await ragSearch(query, topK);
      return { content: [{ type: "text", text: formatHits(hits) }] };
    }
    if (name === "hecate_rag_seed") {
      const rootDir = String(args?.root_dir ?? "");
      if (!rootDir) throw new Error("`root_dir` is required");
      const seedId = String(args?.seed_id ?? "agents-v1");
      const glob = String(args?.glob ?? "**/*.md");
      const sync = args?.sync !== false;
      const result = await ragSeed(rootDir, seedId, glob, sync);
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    }
    throw new Error(`Unknown tool: ${name}`);
  } catch (err) {
    return {
      isError: true,
      content: [
        {
          type: "text",
          text: `hecate-rag-mcp error: ${err instanceof Error ? err.message : String(err)}`,
        },
      ],
    };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);

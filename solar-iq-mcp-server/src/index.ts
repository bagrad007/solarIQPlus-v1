import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "solar-iq-mcp-server",
  version: "1.0.0"
});

function requireEnv(name: string): string {
  const v = process.env[name]?.trim();
  if (!v) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return v;
}

async function solarFetch(path: string): Promise<unknown> {
  const base = requireEnv("SOLAR_IQ_BASE_URL").replace(/\/$/, "");
  const token = requireEnv("SOLAR_IQ_MCP_TOKEN");
  const url = `${base}${path}`;
  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json"
    }
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`SolarIQ ${res.status} ${res.statusText}: ${text.slice(0, 1200)}`);
  }
  return JSON.parse(text) as unknown;
}

function jsonResult(data: unknown) {
  const text = JSON.stringify(data, null, 2);
  return {
    content: [{ type: "text" as const, text }],
    structuredContent: data as Record<string, unknown>
  };
}

const siteIdSchema = z.object({
  site_id: z
    .string()
    .uuid()
    .describe("Site id (UUID) returned by solar_iq_list_sites.")
});

server.registerTool(
  "solar_iq_list_sites",
  {
    title: "List SolarIQ sites",
    description:
      "Lists Sites visible to the MCP acting user (same RLS scope as the web UI). Call first to obtain site UUIDs for other tools.",
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    }
  },
  async () => {
    const data = await solarFetch("/mcp/v1/sites");
    return jsonResult(data);
  }
);

server.registerTool(
  "solar_iq_get_site",
  {
    title: "Get SolarIQ site dashboard data",
    description:
      "Returns public site fields, SiteOperationalSummary, and SiteForecast (weather-backed when coordinates exist). Read-only.",
    inputSchema: siteIdSchema,
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    }
  },
  async ({ site_id }) => {
    const data = await solarFetch(`/mcp/v1/sites/${site_id}`);
    return jsonResult(data);
  }
);

server.registerTool(
  "solar_iq_get_site_diagnostics",
  {
    title: "Get SolarIQ site diagnostics rollup",
    description:
      "Returns the SiteDiagnostics hash used by the Diagnostics React page: today tiles, energy flow, 7-day totals, import/export series, etc. Read-only.",
    inputSchema: siteIdSchema,
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    }
  },
  async ({ site_id }) => {
    const data = await solarFetch(`/mcp/v1/sites/${site_id}/diagnostics`);
    return jsonResult(data);
  }
);

async function main() {
  requireEnv("SOLAR_IQ_BASE_URL");
  requireEnv("SOLAR_IQ_MCP_TOKEN");

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("solar-iq-mcp-server connected (stdio)");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

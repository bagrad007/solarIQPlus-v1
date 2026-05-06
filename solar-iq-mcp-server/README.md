# SolarIQ+ MCP server

## What this is (in plain terms)

**MCP (Model Context Protocol)** is how Cursor (and other clients) attach small **tools** to the AI: the model can call `solar_iq_list_sites`, your machine runs this Node program, which **HTTP-calls your Rails app**, and the JSON result goes back into the chat.

You run **two things**: Rails (your data + RLS) and this **stdio** MCP server (Cursor starts it when needed). They share one secret token.

---

## Automated setup (recommended)

From the **repo root** (after `bundle install`):

```bash
bin/setup-mcp                    # default acting user: site@goose.example
bin/setup-mcp admin@maverick.example   # optional: different User#email
cd solar-iq-mcp-server && npm install && npm run build
bin/rails db:seed                # if you need seeded users
```

This script:

1. Appends `SOLAR_IQ_MCP_TOKEN` and `SOLAR_IQ_MCP_ACTING_USER_EMAIL` to **`.env.development.local`** (gitignored). **`dotenv-rails`** loads them in development.
2. Writes **`.cursor/mcp.json`** (gitignored) so Cursor can start the MCP server with the same token and the correct `cwd`.

Then **restart Cursor**, open **Settings → Tools & MCP**, and enable the **solar-iq** server. Start Rails with `bin/rails server` (or `bin/dev`).

Re-run `bin/setup-mcp` anytime to refresh `.cursor/mcp.json` from your existing token (for example after moving the repo).

---

## Manual setup (if you skip the script)

### 1. Secret and acting user

Generate a token (`openssl rand -hex 32`) and pick a real `User#email` (e.g. after seed: `site@goose.example`).

### 2. Rails env

Set `SOLAR_IQ_MCP_TOKEN` and `SOLAR_IQ_MCP_ACTING_USER_EMAIL` on the Rails process, or add them to `.env.development.local` when using `dotenv-rails`.

### 3. Node package

```bash
cd solar-iq-mcp-server && npm install && npm run build
```

### 4. Cursor

Use **Settings → Tools & MCP** or copy **`.cursor/mcp.json.example`** to **`.cursor/mcp.json`** and fill in `cwd` and token.

### 5. Use it in chat

Start Rails, open this project in Cursor, enable the **solar-iq** MCP server in settings, then ask the agent something like “list my SolarIQ sites” or “summarize diagnostics for site …”. The agent should call the tools automatically when the model supports tool use.

---

## Manual smoke test (optional)

With Rails and env vars set:

```bash
curl -sS -H "Authorization: Bearer $SOLAR_IQ_MCP_TOKEN" \
  http://localhost:3000/mcp/v1/sites | head
```

You should see JSON, not 401/503.

---

## Tools

| Tool | Purpose |
|------|---------|
| `solar_iq_list_sites` | Sites visible to the acting user |
| `solar_iq_get_site` | Site metadata + operational summary + forecast |
| `solar_iq_get_site_diagnostics` | Full `SiteDiagnostics` rollup |

---

## Security notes

- Treat `SOLAR_IQ_MCP_TOKEN` like a password; anyone with it can call the MCP API as the acting user (within RLS).
- Use a dedicated low-privilege user if you only need customer-scoped Sites.

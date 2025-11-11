# ai-workstation

Multi-modal AI desktop and orchestration stack.

This repository now includes:
- A generic local stack for multi-modal AI experimentation.
- A production-focused, MCP-managed Voice Agent architecture integrating Supabase, n8n, RunPod, OpenRouter, and a Hugging Face Space UI.

## Repository Structure

- `ui/` — Gradio chat UI (optionally voice/screenshare).
- `browser-gateway/` — Local headless browser service for screen sharing & automation.
- `n8n-workflows/` — Importable n8n JSON workflow files (chat relay, voice, tools, browser).
- `docs/voice-agent-mcp-architecture.md` — Canonical design and operations reference for the Voice Agent MCP stack.
- `docker-compose.yml` — Stack runner for local dev.

## 1. Local Dev Stack (Generic)

Use this for local experimentation with the included UI, browser gateway, and example workflows.

Quick start:

1. Clone this repository.
2. Run the stack (example):
   - Refer to your environment’s compose/run instructions.
3. Access:
   - Gradio UI: `http://localhost:7860`
   - n8n dashboard: `http://localhost:5678`
   - Headless browser gateway: `http://localhost:8000`
4. Import templates from `n8n-workflows/` into n8n via its dashboard.
5. Add your secrets/API keys (Supabase, LLMs, RunPod, etc.) into n8n credentials and `.env` as needed.

## 2. Voice Agent MCP Stack (Production-style, Single Source of Truth)

The Voice Agent system is a specific, MCP-governed configuration built on this repo. It is documented in detail in:
- `docs/voice-agent-mcp-architecture.md`

Key components (see docs for specifics):

- Hugging Face Space `jblast94/voice-agent-ui`
  - Thin public UI.
  - Talks only to the orchestrator webhook.
  - Uses only:
    - `HF_SUPABASE_URL`
    - `HF_SUPABASE_ANON_KEY`
    - `HF_ORCHESTRATOR_URL`
    - `HF_ORCHESTRATOR_WEBHOOK_SECRET`

- Supabase project `Voice-Agent` (ref: `zwyreijdorbxukffcvxq`)
  - Stores conversations, messages, memory embeddings, and audio artifacts.
  - Schema and RLS managed exclusively via Supabase MCP:
    - `supabase.apply_migration()`
    - `supabase.execute_sql()`
  - pgcrypto + pgvector enabled; idempotent migrations with `IF NOT EXISTS` and guarded policy creation.

- n8n at `https://n8n.jcn.digital`
  - Orchestrator workflow: `Voice-Agent Orchestrator` (ID managed in docs).
  - Responsibilities:
    - Webhook endpoint: `/voice-agent`
    - Secret validation via `ORCHESTRATOR_WEBHOOK_SECRET`
    - RunPod STT/TTS calls using `RUNPOD_API_KEY` + endpoint URLs.
    - OpenRouter LLM calls using `OPENROUTER_API_KEY`.
    - Supabase Voice-Agent access via `SUPABASE_SERVICE_ROLE_KEY_VOICE_AGENT`.
    - Returns JSON to the UI with:
      - `conversation_id`
      - `transcript_text`
      - `assistant_response_text`
      - `tts_audio_url`
  - All workflow lifecycle changes must use `n8n-mcp` tools (see docs).

- RunPod (serverless)
  - STT endpoint and TTS endpoint configured as n8n HTTP Request nodes.
  - Credentials stored only in n8n.

- OpenRouter
  - Used as OpenAI-compatible endpoint from n8n:
    - Base URL `https://openrouter.ai/api/v1`
    - Default model `cognitivecomputations/dolphin-mistral-24b-venice-edition:free`
  - API key stored only in n8n.

## 3. MCP-First Operations

This stack is designed so all critical changes are:
- Automated and auditable via MCP.
- Centralized around n8n and Supabase as the runtime and data plane.

High-level rules (see `docs/voice-agent-mcp-architecture.md` for full policy):

- Supabase:
  - Use `apply_migration()` for schema/RLS.
  - Use `execute_sql()` only for controlled changes.
- n8n:
  - Use `n8n_get_workflow()`, `n8n_update_full_workflow()`, `n8n_update_partial_workflow()`, and `n8n_validate_workflow()` to manage the `Voice-Agent Orchestrator`.
- Secrets:
  - All external API and service-role keys live in:
    - n8n credentials (runtime).
    - Supabase MCP host (management only).
    - Minimal HF Space environment (routing + anon key).
  - No secrets are stored in this repository.

## 4. Voice Agent UI Contract (HF Space ↔ Orchestrator)

The Hugging Face UI must call the orchestrator as follows:

Request (POST `HF_ORCHESTRATOR_URL`):

```json
{
  "secret": "<HF_ORCHESTRATOR_WEBHOOK_SECRET>",
  "conversation_id": "<uuid or null>",
  "audio": "<base64-encoded audio or null>",
  "text": "<optional text if already transcribed>"
}
```

Response (200 OK):

```json
{
  "conversation_id": "<uuid>",
  "transcript_text": "<string or ''>",
  "assistant_response_text": "<string>",
  "tts_audio_url": "<url or data URI>"
}
```

Response (401 Unauthorized):

```json
{
  "error": "unauthorized"
}
```

For full architecture, schema, workflow graph, RLS details, and change-management rules, see:
- `docs/voice-agent-mcp-architecture.md`
# Voice Agent MCP Architecture

This document is the implementation-focused, single source of truth for the live voice assistant system. It describes architecture, MCP tooling, credentials layout (names only), n8n workflow behavior, Supabase schema, Hugging Face Space integration, end-to-end call flow, and change-management rules.

All operational changes MUST be performed via MCP tools and existing secret stores wherever available.

---

## 1. Overview

- Purpose:
  - Single-user, private live voice assistant.
- Core components:
  - Hugging Face Space [`voice-agent-ui`](https://huggingface.co/spaces/jblast94/voice-agent-ui) as thin UI.
  - Supabase project `Voice-Agent` (project ref: `zwyreijdorbxukffcvxq`) as backend datastore (conversations, messages, memory, audio metadata).
  - n8n instance at `https://n8n.jcn.digital` as orchestrator.
  - RunPod (TTS/STT) for audio processing.
  - OpenRouter (model: `cognitivecomputations/dolphin-mistral-24b-venice-edition:free`) as LLM provider.
- Control plane:
  - All cross-service operations are mediated by MCP-compatible tools:
    - `supabase` MCP server (for Supabase management).
    - `n8n-mcp` MCP server (for workflows/orchestration).
    - `context7` MCP server (for documentation lookups only).
  - External APIs (RunPod, OpenRouter) are invoked exclusively from n8n workflows using credentials stored in n8n, not via MCP servers.

High-level behavior:

1. UI sends audio and/or text to the n8n Webhook.
2. n8n:
   - Validates shared secret.
   - Performs STT (if audio).
   - Manages conversation records in Supabase.
   - Calls OpenRouter for LLM response.
   - Optionally persists conversation/messages/embeddings/audio artifacts.
   - Performs TTS for assistant response.
   - Returns structured JSON to UI.
3. Supabase stores all durable conversation/memory/audio metadata.
4. MCP servers provide a fully automatable, auditable control interface for DB schema and orchestrator workflows.

---

## 2. MCP Servers and Tools

### 2.1 n8n MCP

- Base:
  - n8n instance: `https://n8n.jcn.digital`
- Role:
  - System orchestrator.
  - Central integration point for:
    - RunPod STT/TTS.
    - OpenRouter LLM.
    - Supabase Voice-Agent DB (service-role key).
  - All workflow lifecycle and validation actions MUST go through `n8n-mcp` tools.
- Key tools (subset, canonical for this system):
  - [`n8n_create_workflow()`](n8n-mcp:n8n_create_workflow)
  - [`n8n_update_full_workflow()`](n8n-mcp:n8n_update_full_workflow)
  - [`n8n_update_partial_workflow()`](n8n-mcp:n8n_update_partial_workflow)
  - [`n8n_get_workflow()`](n8n-mcp:n8n_get_workflow)
  - [`n8n_get_workflow_details()`](n8n-mcp:n8n_get_workflow_details)
  - [`n8n_list_workflows()`](n8n-mcp:n8n_list_workflows)
  - [`n8n_validate_workflow()`](n8n-mcp:n8n_validate_workflow)
  - [`n8n_health_check()`](n8n-mcp:n8n_health_check)
  - [`n8n_trigger_webhook_workflow()`](n8n-mcp:n8n_trigger_webhook_workflow)
  - [`n8n_get_execution()`](n8n-mcp:n8n_get_execution)
  - [`n8n_list_executions()`](n8n-mcp:n8n_list_executions)
- Usage constraints:
  - All changes to the Voice-Agent orchestrator workflow MUST be:
    - Retrieved, modified, and updated via these tools.
    - Validated with `n8n_validate_workflow` before activation in UI.
  - Direct manual edits in n8n UI should be avoided for reproducibility; if performed, they should be immediately exportable and re-baselined via `n8n-mcp`.

### 2.2 Supabase MCP

- Scope:
  - Management plane for the Voice-Agent Supabase project `zwyreijdorbxukffcvxq` only.
- Role:
  - Apply schema migrations.
  - Introspect tables, extensions, logs, and advisors.
  - Manage Edge Functions for this project.
- Key tools:
  - [`list_projects()`](supabase:list_projects)
  - [`get_project()`](supabase:get_project)
  - [`list_tables()`](supabase:list_tables)
  - [`list_extensions()`](supabase:list_extensions)
  - [`list_migrations()`](supabase:list_migrations)
  - [`apply_migration()`](supabase:apply_migration)
  - [`execute_sql()`](supabase:execute_sql)
  - [`get_project_url()`](supabase:get_project_url)
  - [`get_anon_key()`](supabase:get_anon_key)
  - [`list_edge_functions()`](supabase:list_edge_functions)
  - [`deploy_edge_function()`](supabase:deploy_edge_function)
  - [`get_logs()`](supabase:get_logs)
  - [`get_advisors()`](supabase:get_advisors)
- Usage constraints:
  - All DB and function changes MUST be applied via `apply_migration` (preferred) or `execute_sql` (for controlled, non-DDL ops).
  - No direct manual changes via Supabase UI should be relied upon for long-term configuration.

### 2.3 context7 MCP

- Role:
  - Retrieve up-to-date documentation and examples for libraries/services used by this stack.
- Usage:
  - Read-only support; no runtime or configuration impact.

### 2.4 External Services Integration Model

Explicit design constraint:

- RunPod (STT/TTS), OpenRouter, and the Hugging Face Space:
  - Are integrated via n8n workflow nodes.
  - Use credentials stored exclusively in n8n (for external APIs).
  - Are NOT exposed as MCP servers.
  - Enforces centralized, auditable integration via `n8n-mcp`.

---

## 3. Credentials and Secret Layout (Names Only)

Global principles:

- n8n is the central secret store for external APIs (RunPod, OpenRouter, Supabase service-role).
- Supabase MCP host stores only the management token for Supabase control plane.
- Hugging Face Space stores only minimal routing configuration and anon key.
- No secret values appear in this document or in HF Space logs.

### 3.1 n8n (Primary secret store)

Environment/credential variable names:

- `SUPABASE_URL_VOICE_AGENT`
- `SUPABASE_SERVICE_ROLE_KEY_VOICE_AGENT`
- `OPENROUTER_API_KEY`
- `RUNPOD_API_KEY`
- `RUNPOD_TTS_ENDPOINT_URL` (e.g. `https://api.runpod.ai/v2/8bj9tg60e7nw6y`)
- `RUNPOD_STT_ENDPOINT_URL` (e.g. `https://api.runpod.ai/v2/rxfzl47istu4i2`)
- `ORCHESTRATOR_WEBHOOK_SECRET`

Responsibilities:

- All calls from n8n to:
  - Supabase Voice-Agent project (service-role).
  - OpenRouter.
  - RunPod (STT/TTS).
- The Webhook shared secret to authenticate UI calls.

### 3.2 Supabase MCP Host

- Stores:
  - Supabase management token for MCP-based administration of `zwyreijdorbxukffcvxq`.
- Isolation:
  - Not reused in n8n, HF Space, or UI.
  - Used solely by the supabase MCP server.

### 3.3 Hugging Face Space `jblast94/voice-agent-ui`

Permitted environment variables:

- `HF_SUPABASE_URL`
- `HF_SUPABASE_ANON_KEY`
- `HF_ORCHESTRATOR_URL`
- `HF_ORCHESTRATOR_WEBHOOK_SECRET`

Constraints:

- HF Space:
  - MUST NOT contain:
    - RunPod keys.
    - OpenRouter keys.
    - Supabase service-role keys.
  - Uses only anon key and orchestrator URL/secret for routing.
- n8n:
  - MUST NOT store or host Voice-Agent data in any n8n-owned Supabase project; all durable data is in Voice-Agent Supabase project only.

---

## 4. Supabase Voice-Agent Schema (`zwyreijdorbxukffcvxq`)

All schema and RLS changes MUST be applied via [`apply_migration()`](supabase:apply_migration) using idempotent SQL (with `IF NOT EXISTS` guards).

### 4.1 Extensions

Enabled extensions (at minimum):

- `pgcrypto`
- `vector`

These are required for secure IDs (if used) and vector-based memory embeddings.

### 4.2 Tables

Note: Column definitions reflect the intended implementation for this system. All IDs are UUID unless otherwise specified. Embeddings use `vector(1536)`.

1) `conversations`

- Columns:
  - `id` UUID PRIMARY KEY DEFAULT `gen_random_uuid()`
  - `created_at` TIMESTAMPTZ DEFAULT `now()`
  - `updated_at` TIMESTAMPTZ DEFAULT `now()`
  - `title` TEXT NULL
  - `metadata` JSONB NULL
- Semantics:
  - Represents a logical dialog session.
  - Single-tenant: all rows belong to the one private user/system.

2) `messages`

- Columns:
  - `id` UUID PRIMARY KEY DEFAULT `gen_random_uuid()`
  - `conversation_id` UUID NOT NULL REFERENCES `conversations(id)` ON DELETE CASCADE
  - `created_at` TIMESTAMPTZ DEFAULT `now()`
  - `role` TEXT NOT NULL CHECK (`role` IN ('user','assistant','system'))
  - `content` TEXT NOT NULL
  - `metadata` JSONB NULL
- Semantics:
  - Stores user and assistant messages for each conversation.

3) `memory_embeddings`

- Columns:
  - `id` UUID PRIMARY KEY DEFAULT `gen_random_uuid()`
  - `conversation_id` UUID NULL REFERENCES `conversations(id)` ON DELETE SET NULL
  - `message_id` UUID NULL REFERENCES `messages(id)` ON DELETE CASCADE
  - `created_at` TIMESTAMPTZ DEFAULT `now()`
  - `embedding` vector(1536) NOT NULL
  - `metadata` JSONB NULL
- Semantics:
  - Vector representations for semantic memory / retrieval.

4) `audio_artifacts`

- Columns:
  - `id` UUID PRIMARY KEY DEFAULT `gen_random_uuid()`
  - `conversation_id` UUID NULL REFERENCES `conversations(id)` ON DELETE SET NULL
  - `message_id` UUID NULL REFERENCES `messages(id)` ON DELETE SET NULL
  - `created_at` TIMESTAMPTZ DEFAULT `now()`
  - `direction` TEXT NOT NULL CHECK (`direction` IN ('user','assistant'))
  - `source` TEXT NOT NULL CHECK (`source` IN ('stt_input','tts_output','other'))
  - `url` TEXT NULL
  - `content_base64` TEXT NULL
  - `metadata` JSONB NULL
- Semantics:
  - Tracks audio inputs/outputs; either by URL (e.g. object storage) or embedded base64.

### 4.3 Row-Level Security (RLS)

- RLS:
  - ENABLED on:
    - `conversations`
    - `messages`
    - `memory_embeddings`
    - `audio_artifacts`
- Policies:
  - `single_tenant_*` style policies on each table.
  - `USING (true)` / `WITH CHECK (true)` for the current deployment.
- Design intent:
  - Single-tenant, private deployment.
  - Operational access primarily via service-role key from n8n.
  - Policies are:
    - Created idempotently.
    - Safe to re-apply via `apply_migration` (with `IF NOT EXISTS` checks).
    - Structured so they can be tightened in future without breaking existing flows.
- Future tightening path (recommended):
  - Introduce fixed `user_id` or static tenant ID.
  - Add JWT-based checks for multi-tenant or shared use cases.
  - All such changes MUST be codified and applied via MCP (supabase migrations).

---

## 5. n8n Workflow: "Voice-Agent Orchestrator"

Primary orchestrator workflow:

- Name: `Voice-Agent Orchestrator`
- ID: `VsfQOOnIYe4UFtRf`
- Activation:
  - Toggled in n8n UI.
  - Workflow definition SHOULD be managed via `n8n-mcp` for reproducibility and auditability.

### 5.1 Webhook Trigger

- Endpoint:
  - `POST /voice-agent`
- Expected request body fields:
  - `secret` (string, required)
  - `conversation_id` (string UUID, optional)
  - `audio` (string, base64 or URL, optional)
  - `text` (string, optional)
- Behavior:
  - Triggers the orchestrator for each UI interaction.

### 5.2 Validate Secret

- Logic:
  - Compare incoming `secret` against `ORCHESTRATOR_WEBHOOK_SECRET` stored in n8n.
- Outcomes:
  - If mismatch:
    - Return HTTP 401 with:
      - `{"error":"unauthorized"}`
    - Terminate workflow.
  - If match:
    - Continue.

### 5.3 STT Branch (RunPod STT)

- Condition:
  - Executed if `audio` is present.
- Behavior:
  - Calls `RUNPOD_STT_ENDPOINT_URL` with:
    - `RUNPOD_API_KEY`
    - Audio payload (base64 or referenced URL).
  - Extracts:
    - `transcript_text` from RunPod response.
- Notes:
  - Implementation via n8n HTTP node configured with stored credentials.

### 5.4 Derive User Text

- Behavior:
  - Determine `user_text` as:
    - If `text` provided: use `text`.
    - Else if STT transcript exists: use `transcript_text`.
    - Else: treat as invalid; upstream logic should enforce at least one source.
  - Propagates:
    - `user_text`
    - `conversation_id` (incoming or null).
    - `transcript_text` (may be empty).

### 5.5 Supabase Get/Create Conversation

- Behavior (implemented via Supabase HTTP/DB nodes using `SUPABASE_URL_VOICE_AGENT` and `SUPABASE_SERVICE_ROLE_KEY_VOICE_AGENT`):
  - If `conversation_id` provided:
    - Validate it exists in `conversations`.
    - If missing, optionally create or error (implementation detail, but MUST be deterministic).
  - If no `conversation_id`:
    - Create new row in `conversations`.
    - Return newly created `conversation_id`.
- Implementation expectation:
  - Prefer a dedicated RPC function (e.g. `get_or_create_conversation`) for idempotency.
  - Or a direct insert/select pattern encapsulated in the workflow.

### 5.6 Prepare LLM Payload

- Behavior:
  - Construct OpenRouter `messages` array:
    - `system` message:
      - Encodes assistant persona, safety and single-tenant constraints.
    - Optional context messages:
      - Derived from `memory_embeddings` or system configuration (pluggable).
    - `user` message:
      - From `user_text`.
- Output:
  - Structured payload for OpenRouter Chat Completions.

### 5.7 OpenRouter Chat Completion

- Endpoint:
  - `https://openrouter.ai/api/v1/chat/completions`
- Configuration:
  - `model`: `cognitivecomputations/dolphin-mistral-24b-venice-edition:free`
  - `messages`: from previous step.
  - `Authorization`: `OPENROUTER_API_KEY` (stored in n8n).
- Behavior:
  - Extract `assistant_response_text` from completion result.
- Notes:
  - All handled via n8n HTTP node with appropriate headers and JSON mapping.

### 5.8 (Pluggable) Persistence

Workflow is structured to support insertion of persistence steps without breaking the core contract.

Recommended persistence nodes (using Supabase HTTP/DB nodes with service-role key):

- Insert into `messages`:
  - Store user and assistant messages for the `conversation_id`.
- Insert into `memory_embeddings`:
  - Compute embeddings for relevant texts (if/when embedding service is integrated).
  - Store with `vector(1536)` column and metadata.
- Insert into `audio_artifacts`:
  - Store references for:
    - User input audio (`direction = 'user'`, `source = 'stt_input'`).
    - Assistant TTS output (`direction = 'assistant'`, `source = 'tts_output'`).

All structural modifications or additions MUST be applied via:

- n8n side: `n8n_update_*` tools.
- Supabase side: `apply_migration`.

### 5.9 RunPod TTS (Katie)

- Behavior:
  - Call `RUNPOD_TTS_ENDPOINT_URL` with:
    - `RUNPOD_API_KEY`
    - `voice = "Katie"`
    - `text = assistant_response_text`
  - Extract:
    - `tts_audio_url` or base64 audio.
  - If base64 only:
    - Build data URI (e.g. `data:audio/wav;base64,...`) for direct playback by UI.

### 5.10 Shape Webhook Response

- Response payload fields:
  - `conversation_id`:
    - Existing or newly created UUID.
  - `transcript_text`:
    - From STT branch (or `""` if not applicable).
  - `assistant_response_text`:
    - LLM output string.
  - `tts_audio_url`:
    - URL or data URI for synthesized speech.

### 5.11 Webhook Response

- On success:
  - HTTP 200
  - Body:
    ```json
    {
      "conversation_id": "<uuid>",
      "transcript_text": "<string or ''>",
      "assistant_response_text": "<string>",
      "tts_audio_url": "<url or data URI>"
    }
    ```
- On secret validation failure:
  - HTTP 401
  - Body:
    ```json
    {
      "error": "unauthorized"
    }
    ```

All external calls (RunPod, OpenRouter, Supabase) MUST:

- Be executed via this orchestrator workflow.
- Use n8n-managed credentials.
- Be modified only via `n8n-mcp` tools for consistency.

---

## 6. Hugging Face Space Integration

- Space:
  - ID: `jblast94/voice-agent-ui`
  - Public UI, private behavior via secrets and Webhook.

### 6.1 Orchestrator Contract

- Request:
  - Method: `POST`
  - URL: `HF_ORCHESTRATOR_URL`
  - Body:
    ```json
    {
      "secret": "<HF_ORCHESTRATOR_WEBHOOK_SECRET>",
      "conversation_id": "<uuid or null>",
      "audio": "<base64 or null>",
      "text": "<optional>"
    }
    ```
- Response (200):
  ```json
  {
    "conversation_id": "<uuid>",
    "transcript_text": "<string or ''>",
    "assistant_response_text": "<string>",
    "tts_audio_url": "<url or data URI>"
  }
  ```
- Response (401):
  ```json
  {
    "error": "unauthorized"
  }
  ```

### 6.2 UI Responsibilities

- Capture microphone audio.
- Encode audio:
  - As base64 OR upload and pass accessible URL (depending on implementation).
- Send orchestrator request with:
  - `secret` from `HF_ORCHESTRATOR_WEBHOOK_SECRET`.
  - `conversation_id` from previous response (for continuity), or null for new.
  - `audio` and/or `text`.
- Handle response:
  - Render `transcript_text` (if any).
  - Render `assistant_response_text`.
  - Play `tts_audio_url` (URL or data URI).
- Security constraints:
  - MUST NOT manage or expose:
    - RunPod keys.
    - OpenRouter keys.
    - Supabase service-role key.
  - Restricted to the four allowed env vars only.

---

## 7. Security, Networking, and Operations

### 7.1 Assumptions

- Single-user, private deployment.
- Threat model:
  - Protect external API keys and service-role key.
  - Prevent unauthorized callers from invoking orchestrator.

### 7.2 Trust Boundaries

- n8n:
  - Holds:
    - RunPod API key.
    - OpenRouter API key.
    - Supabase service-role key for Voice-Agent.
    - Webhook secret.
  - Acts as the only component directly calling external APIs with privileged credentials.
- Supabase MCP host:
  - Holds only Supabase management token.
- Hugging Face Space:
  - Holds minimal routing and anon key.
  - No privileged backend secrets.

### 7.3 RLS and Data Access

- RLS:
  - Enabled on all core tables with permissive single-tenant policies.
- Access patterns:
  - UI:
    - Uses anon key; interacts only via orchestrator or any explicitly allowed reads.
  - n8n:
    - Uses service-role key; full backend control.
- Hardening path:
  - Introduce static tenant ID or dedicated user.
  - Enforce policies tied to that identity.
  - Move towards JWT-based checks if multi-user is required, all via migrations through MCP.

### 7.4 Observability

- Via `n8n-mcp`:
  - [`n8n_list_executions()`](n8n-mcp:n8n_list_executions)
  - [`n8n_get_execution()`](n8n-mcp:n8n_get_execution)
  - Use to:
    - Inspect failures for STT/LLM/TTS/Supabase calls.
    - Audit orchestrator behavior.
- Via Supabase MCP:
  - [`get_logs()`](supabase:get_logs)
  - [`get_advisors()`](supabase:get_advisors)
  - Use to:
    - Monitor DB errors.
    - Identify security/performance advisories (e.g., RLS gaps, index suggestions).

---

## 8. Change Management via MCP

All significant changes MUST be managed via MCP tools for reproducibility and auditability.

### 8.1 Database / Schema

- Allowed:
  - Use [`apply_migration()`](supabase:apply_migration) with:
    - Idempotent migrations (e.g., `CREATE TABLE IF NOT EXISTS`, `DO $$ BEGIN ... EXCEPTION WHEN duplicate_object THEN END $$;`).
  - Use [`execute_sql()`](supabase:execute_sql) for:
    - Controlled, non-DDL tasks or inspections.
- Disallowed:
  - Manual schema changes relied upon without corresponding migration.
  - Storing or editing secrets in DB outside controlled mechanisms.

### 8.2 Workflows (n8n)

- Allowed:
  - Use:
    - [`n8n_get_workflow()`](n8n-mcp:n8n_get_workflow)
    - [`n8n_update_full_workflow()`](n8n-mcp:n8n_update_full_workflow)
    - [`n8n_update_partial_workflow()`](n8n-mcp:n8n_update_partial_workflow)
    - [`n8n_validate_workflow()`](n8n-mcp:n8n_validate_workflow)
  - Process:
    - Fetch current JSON.
    - Apply deterministic edits.
    - Validate.
    - Deploy.
- Disallowed:
  - Non-documented, ad-hoc manual edits that are not reflected back into version-controlled definitions.

### 8.3 Secrets

- Allowed:
  - Maintain:
    - External API keys and service-role key only in:
      - n8n credentials.
      - Supabase MCP host (management-only).
      - Minimal HF Space env (routing + anon).
- Disallowed:
  - Spreading secrets across additional ad-hoc locations.
  - Embedding secrets in code, workflows JSON, or HF client script.

All operational practices should converge on:

- MCP as the automation and audit layer.
- n8n as the runtime orchestrator.
- Supabase as the single durable data store.
- HF Space as the minimal, stateless UI.

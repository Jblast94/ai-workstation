# ai-workstation

Multi-modal AI desktop stack:

- **ui/** — Gradio chat UI (optionally voice/screenshare)
- **browser-gateway/** — Local headless browser service for screen sharing & automation
- **n8n-workflows/** — Importable n8n JSON workflow files (chat relay, voice, tools, browser)
- **docker-compose.yml** — Stack runner for local dev

## Quick Start (Local)

1. Clone this repository  
2. Build and run everything:
3. Access Gradio UI at: http://localhost:7860  
n8n dashboard: http://localhost:5678  
Headless browser gateway: http://localhost:8000

4. Import templates from `n8n-workflows/` into n8n via its dashboard

5. Add your secrets/APIs (Supabase, LLMs, RunPod...) into n8n credentials and .env as needed.

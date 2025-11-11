#!/bin/bash
set -e

# Helper to easily create files with parents
write_file() {
  local path="$1"
  # shellcheck disable=SC2188
  mkdir -p "$(dirname "$path")"
  cat > "$path"
}

# ---- FILES ----

write_file "README.md" <<'EOF'
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
EOF

write_file "docker-compose.yml" <<'EOF'
version: "3"
services:
ui:
 build: ./ui
 ports:
   - "7860:7860"
 environment:
   - N8N_API_BASE=http://n8n:5678/webhook
 depends_on:
   - n8n
n8n:
 image: n8nio/n8n
 ports:
   - "5678:5678"
 environment:
   - GENERIC_TIMEZONE=UTC
   - N8N_BASIC_AUTH_ACTIVE=true
   - N8N_BASIC_AUTH_USER=admin
   - N8N_BASIC_AUTH_PASSWORD=strongpassword
   - DB_SQLITE_VACUUM_ON_STARTUP=true
browser-gateway:
 build: ./browser-gateway
 ports:
   - "8000:8000"
   - "5900:5900"
 privileged: true
EOF

write_file "ui/app.py" <<'EOF'
import gradio as gr
import os
import requests

N8N_API_BASE = os.getenv("N8N_API_BASE", "http://localhost:5678/webhook")

def chat(message, history):
 r = requests.post(f"{N8N_API_BASE}/chat", json={"message": message, "history": history})
 response = r.json()
 return history + [[message, response.get("reply", "Error: No reply from n8n")]]

def voice(audio, history):
 with open(audio, "rb") as f:
     files = {"audio": f}
     r = requests.post(f"{N8N_API_BASE}/voice-chat", files=files, data={"history": str(history)})
 response = r.json()
 return history + [[response.get("user_text", ""), response.get("reply", "Error")]], None

def screen_share_start():
 r = requests.post(f"{N8N_API_BASE}/browser/start")
 data = r.json()
 return data.get("stream_url", "Error: No stream URL")

with gr.Blocks() as demo:
 gr.Markdown("# AI Agent (n8n-Orchestrated)")
 chatbox = gr.Chatbot()
 msg = gr.Textbox(label="Message")
 btn = gr.Button("Send")
 audio_in = gr.Audio(sources=["microphone"], type="filepath", label="Talk")
 audio_btn = gr.Button("Send Voice")
 screenshare_btn = gr.Button("Start Screenshare")
 stream_out = gr.Textbox(label="Screenshare Stream URL")

 btn.click(chat, [msg, chatbox], [chatbox])
 audio_btn.click(voice, [audio_in, chatbox], [chatbox, audio_in])
 screenshare_btn.click(screen_share_start, None, [stream_out])

if __name__ == "__main__":
 demo.launch(server_name="0.0.0.0", server_port=7860)
EOF

write_file "ui/requirements.txt" <<'EOF'
gradio
requests
EOF

write_file "browser-gateway/Dockerfile" <<'EOF'
FROM python:3.10
WORKDIR /app
RUN apt-get update && apt-get install -y xvfb chromium-driver chromium-browser
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY gateway.py .
EXPOSE 5900 8000
CMD ["python", "gateway.py"]
EOF

write_file "browser-gateway/requirements.txt" <<'EOF'
flask
selenium
EOF

write_file "browser-gateway/gateway.py" <<'EOF'
from flask import Flask, request, jsonify
from selenium import webdriver
import time

app = Flask(__name__)
drivers = {}

@app.route("/start", methods=["POST"])
def start_browser():
 session_id = str(time.time())
 options = webdriver.ChromeOptions()
 options.add_argument('--headless')
 driver = webdriver.Chrome(options=options)
 drivers[session_id] = driver
 driver.get(request.json.get("url", "https://google.com"))
 return jsonify({"session_id": session_id, "started": True})

@app.route("/navigate", methods=["POST"])
def nav():
 session = request.json["session_id"]
 url = request.json["url"]
 driver = drivers.get(session)
 if driver:
     driver.get(url)
     return jsonify({"navigated": url})
 return jsonify({"error": "Session not found"}), 404

if __name__ == "__main__":
 app.run(host='0.0.0.0', port=8000)
EOF

write_file "n8n-workflows/chat_relay.json" <<'EOF'
{
"name": "Chat Relay",
"nodes": [
 {
   "parameters": { "path": "chat" },
   "id": "Webhook",
   "name": "Webhook",
   "type": "n8n-nodes-base.webhook",
   "typeVersion": 1
 },
 {
   "parameters": {
     "url": "https://YOUR-PROJECT.supabase.co/rest/v1/conversations",
     "method": "POST",
     "bodyParametersUi": {
       "parameter": [
         { "name": "message", "value": "={{$json[\"message\"]}}" }
       ]
     },
     "headersUi": {
       "parameter": [
         { "name": "apikey", "value": "SUPABASE_API_KEY" }
       ]
     }
   },
   "id": "Supabase",
   "name": "Log to Supabase",
   "type": "n8n-nodes-base.httpRequest",
   "typeVersion": 1
 },
 {
   "parameters": {
     "url": "https://openrouter.ai/api/v1/chat/completions",
     "method": "POST",
     "bodyParametersUi": {
       "parameter": [
         { "name": "prompt", "value": "={{$json[\"message\"]}}" }
       ]
     },
     "headersUi": {
       "parameter": [
         { "name": "Authorization", "value": "Bearer LLM_API_KEY" }
       ]
     }
   },
   "id": "LLM",
   "name": "LLM API Call",
   "type": "n8n-nodes-base.httpRequest",
   "typeVersion": 1
 },
 {
   "parameters": { "responseMode": "lastNode" },
   "id": "Respond",
   "name": "Respond",
   "type": "n8n-nodes-base.respondToWebhook",
   "typeVersion": 1
 }
],
"connections": {
 "Webhook": { "main": [ [ { "node": "Log to Supabase", "type": "main", "index": 0 } ] ] },
 "Log to Supabase": { "main": [ [ { "node": "LLM API Call", "type": "main", "index": 0 } ] ] },
 "LLM API Call": { "main": [ [ { "node": "Respond", "type": "main", "index": 0 } ] ] }
}
}
EOF

write_file "n8n-workflows/voice_chat.json" <<'EOF'
{
"name": "Voice Chat Relay",
"nodes": [
 {
   "parameters": { "path": "voice-chat", "options": {} },
   "id": "Webhook2",
   "name": "Webhook",
   "type": "n8n-nodes-base.webhook",
   "typeVersion": 1
 },
 {
   "parameters": {
     "url": "https://runpod.io/your-whisper/stt",
     "method": "POST",
     "bodyParametersUi": {
       "parameter": [
         { "name": "audio", "value": "={{$binary.data}}" }
       ]
     }
   },
   "id": "STT",
   "name": "STT Service",
   "type": "n8n-nodes-base.httpRequest",
   "typeVersion": 1
 },
 {
   "parameters": {
     "url": "https://YOUR-PROJECT.supabase.co/rest/v1/conversations",
     "method": "POST",
     "bodyParametersUi": {
       "parameter": [
         { "name": "message", "value": "={{$json[\"text\"]}}" }
       ]
     },
     "headersUi": {
       "parameter": [
         { "name": "apikey", "value": "SUPABASE_API_KEY" }
       ]
     }
   },
   "id": "Supabase2",
   "name": "Log STT result",
   "type": "n8n-nodes-base.httpRequest",
   "typeVersion": 1
 },
 {
   "parameters": { "responseMode": "lastNode" },
   "id": "Respond2",
   "name": "Respond",
   "type": "n8n-nodes-base.respondToWebhook",
   "typeVersion": 1
 }
],
"connections": {
 "Webhook2": { "main": [ [ { "node": "STT Service", "type": "main", "index": 0 } ] ] },
 "STT Service": { "main": [ [ { "node": "Log STT result", "type": "main", "index": 0 } ] ] },
 "Log STT result": { "main": [ [ { "node": "Respond", "type": "main", "index": 0 } ] ] }
}
}
EOF

write_file "n8n-workflows/tool_call.json" <<'EOF'
{
"name": "Tool Call Relay",
"nodes": [
 {
   "parameters": { "path": "tool-call" },
   "id": "Webhook3",
   "name": "Webhook",
   "type": "n8n-nodes-base.webhook",
   "typeVersion": 1
 },
 {
   "parameters": {
     "url": "https://your-mcp/executor",
     "method": "POST",
     "bodyParametersUi": {
       "parameter": [
         { "name": "command", "value": "={{$json[\"command\"]}}" }
       ]
     }
   },
   "id": "Executor",
   "name": "MCP Executor",
   "type": "n8n-nodes-base.httpRequest",
   "typeVersion": 1
 },
 {
   "parameters": { "responseMode": "lastNode" },
   "id": "Respond3",
   "name": "Respond",
   "type": "n8n-nodes-base.respondToWebhook",
   "typeVersion": 1
 }
],
"connections": {
 "Webhook3": { "main": [ [ { "node": "MCP Executor", "type": "main", "index": 0 } ] ] },
 "MCP Executor": { "main": [ [ { "node": "Respond", "type": "main", "index": 0 } ] ] }
}
}
EOF

write_file "n8n-workflows/browser_gateway.json" <<'EOF'
{
"name": "Browser Gateway Relay",
"nodes": [
 {
   "parameters": { "path": "browser/start" },
   "id": "Webhook4",
   "name": "Webhook",
   "type": "n8n-nodes-base.webhook",
   "typeVersion": 1
 },
 {
   "parameters": {
     "url": "http://browser-gateway:8000/start",
     "method": "POST",
     "bodyParametersUi": {
       "parameter": [ { "name": "url", "value": "={{$json[\"url\"] || 'https://google.com'}}" } ]
     }
   },
   "id": "BrowserStart",
   "name": "Start Browser",
   "type": "n8n-nodes-base.httpRequest",
   "typeVersion": 1
 },
 {
   "parameters": { "responseMode": "lastNode" },
   "id": "Respond4",
   "name": "Respond",
   "type": "n8n-nodes-base.respondToWebhook",
   "typeVersion": 1
 }
],
"connections": {
 "Webhook4": { "main": [ [ { "node": "Start Browser", "type": "main", "index": 0 } ] ] },
 "Start Browser": { "main": [ [ { "node": "Respond", "type": "main", "index": 0 } ] ] }
}
}
EOF

echo "✅ All project files and directories created!"
echo "You can now zip this folder or git commit/push to your repository."
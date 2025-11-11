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

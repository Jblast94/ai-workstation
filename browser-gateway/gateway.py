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

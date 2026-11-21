#!/usr/bin/env python3
"""Wolffe TV v3: local-only Roku TV input dashboard."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from urllib.parse import urlparse
import json
import os
import threading
import time

ROOT = Path(__file__).resolve().parent
CONFIG_PATH = ROOT / "config.json"

ACTIONS = {
    "hdmi1": "InputHDMI1", "hdmi2": "InputHDMI2", "hdmi3": "InputHDMI3",
    "av": "InputAV1", "home": "Home", "back": "Back", "up": "Up",
    "down": "Down", "left": "Left", "right": "Right", "select": "Select",
}

def load_config():
    if not CONFIG_PATH.exists():
        raise SystemExit("Missing config.json. Run run.command to complete setup.")
    data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    tv_ip = str(data.get("tv_ip", "")).strip()
    tv_name = str(data.get("tv_name", "Wolffe TV")).strip() or "Wolffe TV"
    if not tv_ip:
        raise SystemExit("config.json must contain a tv_ip value.")
    return tv_ip, tv_name, int(data.get("port", 8787))

TV_IP, TV_NAME, SERVER_PORT = load_config()

def roku_post(key):
    req = Request(f"http://{TV_IP}:8060/keypress/{key}", data=b"", method="POST")
    with urlopen(req, timeout=3) as response:
        return response.status

def roku_status():
    with urlopen(f"http://{TV_IP}:8060/query/device-info", timeout=3) as response:
        return response.status == 200

def restart_setup():
    time.sleep(0.8)
    os.execl(str(ROOT / "run.command"), str(ROOT / "run.command"))

class Handler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        clean = urlparse(path).path.lstrip("/") or "index.html"
        return str(ROOT / clean)

    def send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/status":
            try: self.send_json(200, {"online": roku_status()})
            except Exception: self.send_json(200, {"online": False})
            return
        if path == "/api/config":
            self.send_json(200, {"tv_name": TV_NAME, "version": "v3"})
            return
        super().do_GET()

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/setup-reset":
            try:
                CONFIG_PATH.unlink(missing_ok=True)
                self.send_json(200, {"ok": True, "message": "Setup reset. Continue in Terminal."})
                threading.Thread(target=restart_setup, daemon=True).start()
            except Exception as exc:
                self.send_json(500, {"ok": False, "error": str(exc)})
            return
        if not path.startswith("/api/action/"):
            self.send_json(404, {"ok": False, "error": "Unknown endpoint"})
            return
        action = path.rsplit("/", 1)[-1]
        key = ACTIONS.get(action)
        if key is None:
            self.send_json(400, {"ok": False, "error": "Unknown action"})
            return
        try:
            roku_post(key)
            self.send_json(200, {"ok": True, "action": action})
        except (URLError, HTTPError, TimeoutError) as exc:
            self.send_json(502, {"ok": False, "error": f"TV request failed: {exc}"})
        except Exception as exc:
            self.send_json(500, {"ok": False, "error": str(exc)})

    def log_message(self, fmt, *args):
        print(f"[{self.log_date_time_string()}] {fmt % args}")

if __name__ == "__main__":
    os.chdir(ROOT)
    server = ThreadingHTTPServer(("0.0.0.0", SERVER_PORT), Handler)
    print(f"{TV_NAME} - Wolffe TV v3 is running.")
    print(f"On this Mac: http://localhost:{SERVER_PORT}")
    print(f"From another device: http://YOUR-MAC-IP:{SERVER_PORT}")
    print("Press Control+C to stop.")
    try: server.serve_forever()
    except KeyboardInterrupt: print("\nStopping Wolffe TV.")
    finally: server.server_close()

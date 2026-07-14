#!/usr/bin/env python3
"""本地预览 fnOS Web UI，并提供不会操作硬件的模拟 CGI API。"""

from __future__ import annotations

import argparse
import json
import math
import mimetypes
import threading
import time
import webbrowser
from collections import OrderedDict
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse


ROOT = Path(__file__).resolve().parent.parent
APP_ROOT = ROOT / "App.Native.UGreenLED" / "app"
WWW_ROOT = APP_ROOT / "www"
DEFAULT_SETTINGS = APP_ROOT / "server" / "default_settings.conf"
APP_BASE = "/cgi/ThirdParty/App.Native.UGreenLED"
STATIC_BASE = f"{APP_BASE}/index.cgi/"
API_BASE = f"{APP_BASE}/api.cgi"


def parse_ini(raw: str) -> OrderedDict[str, OrderedDict[str, str]]:
    data: OrderedDict[str, OrderedDict[str, str]] = OrderedDict()
    section = ""
    for source_line in raw.splitlines():
        line = source_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            data.setdefault(section, OrderedDict())
        elif section and "=" in line:
            key, value = line.split("=", 1)
            data[section][key.strip()] = value.strip()
    return data


def dump_ini(data: OrderedDict[str, OrderedDict[str, str]]) -> str:
    lines: list[str] = []
    for section, values in data.items():
        if lines:
            lines.append("")
        lines.append(f"[{section}]")
        lines.extend(f"{key}={value}" for key, value in values.items())
    return "\n".join(lines) + "\n"


class PreviewState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.settings = parse_ini(DEFAULT_SETTINGS.read_text(encoding="utf-8"))
        self.daemon = "running"
        self.remap_count = 0

    @property
    def mode(self) -> str:
        return self.settings.setdefault("mode", OrderedDict()).get("global", "smart")

    def update_settings(self, body: str) -> None:
        with self.lock:
            for source_line in body.splitlines():
                line = source_line.strip()
                if not line or "." not in line or "=" not in line:
                    continue
                compound, value = line.split("=", 1)
                section, key = compound.split(".", 1)
                self.settings.setdefault(section, OrderedDict())[key] = value

    def set_mode(self, mode: str) -> None:
        if mode in {"off", "on", "smart"}:
            with self.lock:
                self.settings.setdefault("mode", OrderedDict())["global"] = mode


STATE = PreviewState()


class PreviewHandler(BaseHTTPRequestHandler):
    server_version = "UGreenLEDPreview/1.4"

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"[{self.log_date_time_string()}] {fmt % args}")

    def send_json(self, payload: dict, status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self.send_response(HTTPStatus.FOUND)
            self.send_header("Location", STATIC_BASE)
            self.end_headers()
            return
        if parsed.path.startswith(API_BASE):
            self.handle_api("GET", parsed.path[len(API_BASE) :] or "/", parse_qs(parsed.query), "")
            return
        if parsed.path.startswith(STATIC_BASE):
            relative = unquote(parsed.path[len(STATIC_BASE) :]) or "index.html"
            self.serve_static(relative)
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if not parsed.path.startswith(API_BASE):
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        length = min(int(self.headers.get("Content-Length", "0") or 0), 65536)
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        self.handle_api("POST", parsed.path[len(API_BASE) :] or "/", parse_qs(parsed.query), body)

    def serve_static(self, relative: str) -> None:
        target = (WWW_ROOT / relative).resolve()
        try:
            target.relative_to(WWW_ROOT.resolve())
        except ValueError:
            self.send_error(HTTPStatus.BAD_REQUEST)
            return
        if not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        body = target.read_bytes()
        if target.suffix == ".woff2":
            mime = "font/woff2"
        elif target.suffix == ".woff":
            mime = "font/woff"
        else:
            mime = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", f"{mime}; charset=utf-8" if mime.startswith("text/") else mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def handle_api(self, method: str, path: str, query: dict[str, list[str]], body: str) -> None:
        now = time.time()
        if path == "/status":
            rx = int(1150 + abs(math.sin(now / 4.2)) * 9800)
            tx = int(380 + abs(math.cos(now / 5.1)) * 2400)
            self.send_json({
                "ok": True,
                "daemon": STATE.daemon,
                "mode": STATE.mode,
                "network": "vpn",
                "network_label": "外网",
                "net_domestic": 1,
                "net_overseas": 1,
                "net_rx_kbps": rx,
                "net_tx_kbps": tx,
                "net_total_kbps": rx + tx,
                "updated_at": int(now),
                "led_status": "power: on  RGB(100,100,100)  brightness=40\nnetdev: blink  RGB(160,0,255)  brightness=64\ndisk1: on  RGB(0,255,0)  brightness=128\ndisk2: on  RGB(255,255,0)  brightness=64\ndisk3: standby  RGB(0,100,255)  brightness=40",
            })
            return
        if path == "/mapping":
            speeds = [
                ("/dev/sda", "disk1", "active", int(320 + abs(math.sin(now / 2.5)) * 3500), int(120 + abs(math.cos(now / 3.2)) * 880)),
                ("/dev/sdb", "disk2", "idle", 0, int(abs(math.sin(now / 6)) * 22)),
                ("/dev/sdc", "disk3", "standby", 0, 0),
            ]
            self.send_json({"ok": True, "mapping": [
                {"device": dev, "led": led, "state": state, "read_kbps": read, "write_kbps": write, "total_kbps": read + write, "updated_at": int(now)}
                for dev, led, state, read, write in speeds
            ]})
            return
        if path == "/settings":
            if method == "POST":
                STATE.update_settings(body)
                self.send_json({"ok": True})
            else:
                with STATE.lock:
                    raw = dump_ini(STATE.settings)
                self.send_json({"ok": True, "raw": raw})
            return
        if path == "/mode":
            mode = (query.get("mode") or [STATE.mode])[0]
            STATE.set_mode(mode)
            self.send_json({"ok": True, "mode": STATE.mode})
            return
        if path == "/remap":
            STATE.remap_count += 1
            self.send_json({"ok": True, "message": "已重新检测 3 块硬盘", "disk_count": 3})
            return
        if path == "/daemon/start":
            STATE.daemon = "running"
            self.send_json({"ok": True, "daemon": STATE.daemon, "message": "后台已启动"})
            return
        if path == "/daemon/stop":
            STATE.daemon = "stopped"
            self.send_json({"ok": True, "daemon": STATE.daemon, "message": "后台已停止"})
            return
        self.send_json({"ok": False, "error": "unknown preview route", "path": path}, HTTPStatus.NOT_FOUND)


def main() -> None:
    parser = argparse.ArgumentParser(description="预览绿联 LED 灯控 Web UI")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--no-open", action="store_true", help="不自动打开浏览器")
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), PreviewHandler)
    url = f"http://{args.host}:{args.port}{STATIC_BASE}"
    print(f"本地预览已启动：{url}")
    print("按 Ctrl+C 停止。预览数据为模拟数据，不会访问 NAS 或控制 LED。")
    if not args.no_open:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n预览已停止。")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

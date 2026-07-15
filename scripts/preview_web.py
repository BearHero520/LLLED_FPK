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
MANIFEST = ROOT / "App.Native.UGreenLED" / "manifest"
APP_BASE = "/cgi/ThirdParty/App.Native.UGreenLED"
STATIC_BASE = f"{APP_BASE}/index.cgi/"
API_BASE = f"{APP_BASE}/api.cgi"


def manifest_version() -> str:
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        if line.startswith("version") and "=" in line:
            return line.split("=", 1)[1].strip()
    return "unknown"


CURRENT_VERSION = manifest_version()


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
        self.lab_active = False
        self.lab_highlight = ""
        self.driver_loaded = False
        self.lab_slots = [f"disk{index}" for index in range(1, 7)]
        self.lab_disks = [
            {"device": "/dev/sda", "hctl": "0:0:0:0", "serial": "ZHZ4A001", "model": "ST8000VN004", "size": "7.3T", "transport": "sata", "supported": True},
            {"device": "/dev/sdb", "hctl": "1:0:0:0", "serial": "ZHZ4A002", "model": "ST8000VN004", "size": "7.3T", "transport": "sata", "supported": True},
            {"device": "/dev/sdc", "hctl": "2:0:0:0", "serial": "WX42D003", "model": "WDC WD120EFBX", "size": "10.9T", "transport": "sata", "supported": True},
            {"device": "/dev/sdd", "hctl": "3:0:0:0", "serial": "WX42D004", "model": "WDC WD120EFBX", "size": "10.9T", "transport": "sata", "supported": True},
            {"device": "/dev/sde", "hctl": "4:0:0:0", "serial": "ZA20E005", "model": "TOSHIBA MG08ACA16TE", "size": "14.6T", "transport": "sata", "supported": True},
            {"device": "/dev/sdf", "hctl": "5:0:0:0", "serial": "ZA20E006", "model": "TOSHIBA MG08ACA16TE", "size": "14.6T", "transport": "sata", "supported": True},
        ]
        self.auto_led_map = {disk["device"]: self.lab_slots[index] for index, disk in enumerate(self.lab_disks)}
        self.position_led_map = dict(self.auto_led_map)
        self.identity_led_map = dict(self.auto_led_map)

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

    def active_led_map(self) -> dict[str, str]:
        mode = self.settings.setdefault("behavior", OrderedDict()).get("disk_map_mode", "auto")
        if mode == "position":
            return self.position_led_map
        if mode == "disk":
            return self.identity_led_map
        return self.auto_led_map

    def lab_payload(self, message: str = "") -> dict:
        with self.lock:
            payload = {
                "ok": True,
                "active": self.lab_active,
                "mode": self.settings.setdefault("behavior", OrderedDict()).get("disk_map_mode", "auto"),
                "product_name": "DXP6800 Pro（预览）",
                "profile": "dxp6800",
                "session_ttl": 1200,
                "slots": [{"led": slot, "position": index} for index, slot in enumerate(self.lab_slots, 1)],
                "disks": [
                    dict(
                        disk,
                        position=index,
                        led=self.active_led_map().get(disk["device"], ""),
                        position_led=self.position_led_map.get(disk["device"], ""),
                        identity_led=self.identity_led_map.get(disk["device"], ""),
                        position_supported=bool(disk["hctl"]),
                        identity_supported=bool(disk["serial"]),
                    )
                    for index, disk in enumerate(self.lab_disks, 1)
                ],
            }
        if message:
            payload["message"] = message
        return payload

    def save_identity_mapping(self, body: str) -> None:
        mapping: dict[str, str] = {}
        used_leds: set[str] = set()
        serial_devices = {disk["serial"]: disk["device"] for disk in self.lab_disks}
        for source_line in body.splitlines():
            line = source_line.strip()
            if not line:
                continue
            led, device, serial = line.split("|", 2)
            if led not in self.lab_slots or serial_devices.get(serial) != device or device in mapping or led in used_leds:
                raise ValueError("映射数据无效")
            mapping[device] = led
            used_leds.add(led)
        if not mapping:
            raise ValueError("请至少绑定一块硬盘")
        with self.lock:
            self.identity_led_map = mapping
            self.settings.setdefault("behavior", OrderedDict())["disk_map_mode"] = "disk"
            self.lab_active = False
            self.lab_highlight = ""

    def save_position_mapping(self, body: str) -> None:
        mapping: dict[str, str] = {}
        used_leds: set[str] = set()
        hctl_devices = {disk["hctl"]: disk["device"] for disk in self.lab_disks}
        for source_line in body.splitlines():
            line = source_line.strip()
            if not line:
                continue
            led, device, hctl = line.split("|", 2)
            if led not in self.lab_slots or hctl_devices.get(hctl) != device or device in mapping or led in used_leds:
                raise ValueError("位置映射数据无效")
            mapping[device] = led
            used_leds.add(led)
        if not mapping:
            raise ValueError("请至少绑定一个硬盘位置")
        with self.lock:
            self.position_led_map = mapping
            self.settings.setdefault("behavior", OrderedDict())["disk_map_mode"] = "position"
            self.lab_active = False
            self.lab_highlight = ""

    def reset_lab_mapping(self) -> None:
        with self.lock:
            self.settings.setdefault("behavior", OrderedDict())["disk_map_mode"] = "auto"
            self.lab_active = False
            self.lab_highlight = ""


STATE = PreviewState()


class PreviewHandler(BaseHTTPRequestHandler):
    server_version = "UGreenLEDPreview/1.6.8"

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
                "lab_mapping_active": STATE.lab_active,
                "led_status": "power: on  RGB(100,100,100)  brightness=40\nnetdev: blink  RGB(160,0,255)  brightness=64\ndisk1: on  RGB(0,255,0)  brightness=128\ndisk2: on  RGB(255,255,0)  brightness=64\ndisk3: standby  RGB(0,100,255)  brightness=40",
            })
            return
        if path == "/mapping":
            states = ["active", "idle", "standby", "idle", "deep_sleep", "active"]
            speeds = [
                (disk["device"], STATE.active_led_map().get(disk["device"], ""), states[index],
                 int(abs(math.sin(now / (2.5 + index))) * (3500 if index in {0, 5} else 80)),
                 int(abs(math.cos(now / (3.2 + index))) * (880 if index in {0, 5} else 35)))
                for index, disk in enumerate(STATE.lab_disks)
                if disk["device"] in STATE.active_led_map()
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
        if path == "/hardware/status":
            with STATE.lock:
                hardware = STATE.settings.setdefault("hardware", OrderedDict())
                configured = hardware.get("backend", "auto")
                profile = hardware.get("profile", "auto")
                protocol = hardware.get("write_protocol", "auto")
                selected_profile = "dxp6800" if profile == "auto" else profile
                profile_meta = {
                    "dx4600": ("UGREEN DX4600 Pro", "stable", 4, 1, True),
                    "dx4700": ("UGREEN DX4700+", "stable", 4, 1, True),
                    "dxp2800": ("UGREEN DXP2800", "stable", 2, 1, True),
                    "dxp2800_gt": ("UGREEN DXP2800 GT", "unverified", 2, 1, True),
                    "dxp4800": ("UGREEN DXP4800", "stable", 4, 1, True),
                    "dxp4800_plus": ("UGREEN DXP4800 Plus", "stable", 4, 1, True),
                    "dxp4800_pro": ("UGREEN DXP4800 Pro", "unverified", 4, 1, True),
                    "dxp4800_gt": ("UGREEN DXP4800 GT", "experimental", 4, 1, True),
                    "dxp6800": ("UGREEN DXP6800 Pro", "stable", 6, 1, True),
                    "dxp8800": ("UGREEN DXP8800 Plus", "stable", 8, 1, True),
                    "dxp480t_plus": ("UGREEN DXP480T / DXP480T Plus", "limited", 0, 0, False),
                    "idx6011": ("UGREEN iDX6011", "experimental", 6, 1, True),
                    "idx6011_pro": ("UGREEN iDX6011 Pro", "experimental", 6, 2, True),
                }
                profile_name, support, disk_count, netdev_count, driver_supported = profile_meta.get(
                    selected_profile, ("未知机型", "unknown", 0, 1, True)
                )
                effective_protocol = (
                    "smbus-block"
                    if protocol == "auto" and selected_profile in {"dxp4800_gt", "idx6011", "idx6011_pro"}
                    else "legacy" if protocol == "auto" else protocol
                )
                if selected_profile == "dxp480t_plus" and configured != "sysfs":
                    active = "power-0x26"
                else:
                    active = "sysfs" if STATE.driver_loaded and configured != "cli" else "cli"
            self.send_json({
                "ok": True,
                "product_name": "DXP6800 Pro（预览）",
                "profile": selected_profile,
                "profile_name": profile_name,
                "support": support,
                "cli_version": "v0.4-beta",
                "write_protocol": effective_protocol,
                "write_protocol_configured": protocol,
                "disk_count": disk_count,
                "netdev_count": netdev_count,
                "backend_configured": configured,
                "backend_active": active,
                "cli_ready": True,
                "driver_loaded": STATE.driver_loaded,
                "sysfs_ready": STATE.driver_loaded,
                "dkms_ready": True,
                "headers_ready": True,
                "driver_conflict": False,
                "dkms_installed": STATE.driver_loaded,
                "dkms_registered": STATE.driver_loaded,
                "driver_managed": STATE.driver_loaded,
                "driver_supported": driver_supported,
                "kernel": "6.12.0-preview",
            })
            return
        if path == "/update/check":
            parts = CURRENT_VERSION.split(".")
            latest = ".".join(parts[:-1] + [str(int(parts[-1]) + 1)]) if all(part.isdigit() for part in parts) else "1.4.7"
            tag = f"v{latest}"
            self.send_json({
                "ok": True,
                "reachable": True,
                "current_version": CURRENT_VERSION,
                "latest_version": latest,
                "latest_tag": tag,
                "release_url": f"https://github.com/BearHero520/LLLED_FPK/releases/tag/{tag}",
                "download_url": f"https://github.com/BearHero520/LLLED_FPK/releases/download/{tag}/App.Native.UGreenLED.fpk",
                "checked_at": int(now),
            })
            return
        if path == "/lab/mapping/status":
            self.send_json(STATE.lab_payload())
            return
        if path == "/driver/install":
            with STATE.lock:
                STATE.driver_loaded = True
                STATE.settings.setdefault("hardware", OrderedDict())["backend"] = "sysfs"
            self.send_json({"ok": True, "message": "内核驱动已安装并切换到 sysfs 后端"})
            return
        if path == "/driver/unload":
            with STATE.lock:
                STATE.driver_loaded = False
                STATE.settings.setdefault("hardware", OrderedDict())["backend"] = "cli"
            self.send_json({"ok": True, "message": "内核驱动已卸载，已切换到 CLI 后端"})
            return
        if path == "/lab/mapping/start":
            with STATE.lock:
                STATE.lab_active = True
                STATE.lab_highlight = ""
            self.send_json(STATE.lab_payload("检测模式已启动，全部硬盘灯已点亮"))
            return
        if path == "/lab/mapping/highlight":
            led = (query.get("led") or [""])[0]
            if not STATE.lab_active:
                self.send_json({"ok": False, "error": "检测会话已结束，请重新开始"})
                return
            if led not in STATE.lab_slots:
                self.send_json({"ok": False, "error": "无法点亮指定盘位"})
                return
            with STATE.lock:
                STATE.lab_highlight = led
            self.send_json(STATE.lab_payload(f"{led} 正在闪烁"))
            return
        if path == "/lab/mapping/save":
            try:
                STATE.save_identity_mapping(body)
            except (ValueError, TypeError) as error:
                self.send_json({"ok": False, "error": str(error)})
                return
            self.send_json(STATE.lab_payload("按硬盘绑定已保存"))
            return
        if path == "/lab/position/save":
            try:
                STATE.save_position_mapping(body)
            except (ValueError, TypeError) as error:
                self.send_json({"ok": False, "error": str(error)})
                return
            self.send_json(STATE.lab_payload("灯光与硬盘位置绑定已保存"))
            return
        if path == "/lab/mapping/cancel":
            with STATE.lock:
                STATE.lab_active = False
                STATE.lab_highlight = ""
            self.send_json(STATE.lab_payload("已退出检测模式，原映射保持不变"))
            return
        if path == "/lab/mapping/reset":
            STATE.reset_lab_mapping()
            self.send_json(STATE.lab_payload("已恢复自动 HCTL 映射"))
            return
        if path == "/mode":
            mode = (query.get("mode") or [STATE.mode])[0]
            STATE.set_mode(mode)
            self.send_json({"ok": True, "mode": STATE.mode})
            return
        if path == "/remap":
            STATE.remap_count += 1
            STATE.reset_lab_mapping()
            self.send_json({"ok": True, "message": "已重新检测 6 块硬盘", "disk_count": 6})
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

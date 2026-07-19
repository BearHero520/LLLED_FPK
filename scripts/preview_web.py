#!/usr/bin/env python3
"""本地预览 fnOS Web UI，并提供不会操作硬件的模拟 CGI API。"""

from __future__ import annotations

import argparse
import json
import math
import mimetypes
import re
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

PROFILE_META = {
    "dx4600": ("UGREEN DX4600 Pro", "stable", 4, 1, True),
    "dx4700": ("UGREEN DX4700+", "stable", 4, 1, True),
    "dxp2800": ("UGREEN DXP2800", "stable", 2, 1, True),
    "dxp2800_gt": ("UGREEN DXP2800 GT", "unverified", 2, 1, True),
    "dxp4800": ("UGREEN DXP4800", "stable", 4, 1, True),
    "dxp4800_plus": ("UGREEN DXP4800 Plus", "stable", 4, 1, True),
    "dxp4800_pro": ("UGREEN DXP4800 Pro", "unverified", 4, 1, True),
    "dxp4800s": ("UGREEN DXP4800S", "experimental", 4, 1, True),
    "dxp4800_gt": ("UGREEN DXP4800 GT", "experimental", 4, 1, True),
    "dxp6800": ("UGREEN DXP6800 Pro", "stable", 6, 1, True),
    "dxp8800": ("UGREEN DXP8800 Plus", "stable", 8, 1, True),
    "dxp480t_plus": ("UGREEN DXP480T / DXP480T Plus", "limited", 0, 0, False),
    "idx6011": ("UGREEN iDX6011", "experimental", 6, 1, True),
    "idx6011_pro": ("UGREEN iDX6011 Pro", "experimental", 6, 2, True),
}


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
        self.bios_cpu_pwm = 118
        self.bios_sys_pwm = 96
        self.bios_sys2_pwm = 96
        self.bios_cpu_manual = False
        self.bios_sys_manual = False
        self.bios_sys2_manual = False
        self.bios_startup = "last"
        self.log_level = "info"
        self.logs = [
            "[2026-07-16T22:40:01+0800] [INFO] [service] [pid=2401] [event=service.start_requested] [source=main:main:51] msg=\"收到应用启动请求\" | kernel=\"6.12.0-preview\" cli=\"server/bin/ugreen_leds_cli\"",
            "[2026-07-16T22:40:02+0800] [INFO] [daemon] [pid=2417] [event=daemon.started] [source=led_daemon.sh:daemon_loop:281] msg=\"LED 守护循环已启动\" | mode=\"smart\" backend=\"cli\"",
            "[2026-07-16T22:40:03+0800] [INFO] [daemon] [pid=2417] [event=mapping.ready] [source=led_daemon.sh:ensure_mapping:119] msg=\"硬盘灯映射已生成\" | count=\"6\" profile=\"dxp6800\"",
            "[2026-07-16T22:41:10+0800] [WARN] [api] [pid=2538] [request=req-preview-warning] [event=request.rejected] [source=api.cgi:main:848] msg=\"API 请求未成功\" | method=\"POST\" path=\"/led/set\" error=\"示例：LED CLI 命令超时\"",
        ]
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

    def add_log(self, level: str, event: str, message: str, **context: object) -> None:
        timestamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        fields = " ".join(f'{key}="{str(value).replace(chr(10), " ")[:240]}"' for key, value in context.items())
        line = f'[{timestamp}] [{level.upper()}] [preview] [pid=1] [event={event}] [source=preview_web.py:handle_api:0] msg="{message}"'
        if fields:
            line += f" | {fields}"
        with self.lock:
            self.logs.append(line)
            del self.logs[:-2000]

    def configure_profile(self, profile: str) -> None:
        if profile not in PROFILE_META:
            raise ValueError(f"未知预览机型：{profile}")
        with self.lock:
            self.settings.setdefault("hardware", OrderedDict())["profile"] = profile

    def selected_profile(self) -> str:
        profile = self.settings.setdefault("hardware", OrderedDict()).get("profile", "auto")
        return "dxp6800" if profile == "auto" else profile

    def profile_meta(self) -> tuple[str, str, int, int, bool]:
        return PROFILE_META.get(self.selected_profile(), ("未知机型", "unknown", 0, 1, True))

    def bios_payload(self, message: str = "") -> dict[str, object]:
        profile = self.selected_profile()
        supported = profile in {"dxp4800_plus", "dxp4800_pro", "dxp4800s", "dxp480t_plus", "dxp6800"}
        is_480t = profile == "dxp480t_plus"
        is_4800s = profile == "dxp4800s"
        is_6800 = profile == "dxp6800"
        payload: dict[str, object] = {
            "ok": True,
            "supported": supported,
            "available": supported,
            "model": "dxp6800pro" if is_6800 else profile if supported else "unknown",
            "experimental": is_4800s or is_6800,
            "min_pwm": 64 if is_4800s else 40,
            "fan_write_target": "all" if is_480t else "sys",
            "cpu_fan_present": not is_4800s,
            "fan_mode_writable": False,
            "pwm_readable": not is_4800s,
            "write_confirmation_required": is_4800s or is_6800,
            "product_name": f"{self.profile_meta()[0]}（预览）",
            "backend": "ugreenctl" if supported else "unavailable",
            "chip_id": "0x8613" if supported else "",
            "revision": 2 if supported else 0,
            "cpu_pwm": self.bios_cpu_pwm if supported and not is_4800s else -1,
            "sys_pwm": self.bios_sys_pwm if supported and not is_4800s else -1,
            "sys2_pwm": self.bios_sys2_pwm if is_480t or is_6800 else -1,
            "cpu_rpm": 1120 if is_480t else 1280 if supported and not is_4800s else 0,
            "sys_rpm": 860 if is_480t else 920 if is_4800s else 940 if supported else 0,
            "sys2_rpm": 790 if is_480t else 820 if is_6800 else 0,
            "cpu_manual": self.bios_cpu_manual if supported else False,
            "sys_manual": self.bios_sys_manual if supported else False,
            "sys2_manual": self.bios_sys2_manual if is_480t or is_6800 else False,
            "startup": self.bios_startup if supported else "unknown",
            "error": "" if supported else "BIOS 控制仅支持 DXP4800 Plus / Pro、DXP4800S、DXP480T Plus 与 DXP6800 Pro",
        }
        if message:
            payload["message"] = message
        return payload

    @property
    def mode(self) -> str:
        return self.settings.setdefault("mode", OrderedDict()).get("global", "smart")

    def update_settings(self, body: str) -> None:
        updates: list[tuple[str, str, str]] = []
        identifier = re.compile(r"^[A-Za-z0-9_-]+$")
        for source_line in body.splitlines():
            line = source_line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                raise ValueError("invalid settings payload")
            compound, value = line.split("=", 1)
            if "." not in compound:
                raise ValueError("invalid settings payload")
            section, key = compound.split(".", 1)
            if not identifier.fullmatch(section) or not identifier.fullmatch(key):
                raise ValueError("invalid settings payload")
            updates.append((section, key, value))

        with self.lock:
            for section, key, value in updates:
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
            profile = self.selected_profile()
            profile_name, _, disk_count, _, _ = self.profile_meta()
            slots = self.lab_slots[:disk_count]
            disks = self.lab_disks[:disk_count]
            payload = {
                "ok": True,
                "active": self.lab_active,
                "mode": self.settings.setdefault("behavior", OrderedDict()).get("disk_map_mode", "auto"),
                "product_name": f"{profile_name}（预览）",
                "profile": profile,
                "session_ttl": 1200,
                "slots": [{"led": slot, "position": index} for index, slot in enumerate(slots, 1)],
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
                    for index, disk in enumerate(disks, 1)
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
    server_version = "UGreenLEDPreview/1.8.7"

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"[{self.log_date_time_string()}] {fmt % args}")

    def send_json(self, payload: dict, status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        request_id = self.headers.get("X-Request-ID", "")
        if not 8 <= len(request_id) <= 64 or not all(
            character.isascii() and (character.isalnum() or character in "._:-") for character in request_id
        ):
            request_id = f"preview-{int(time.time() * 1000)}-{threading.get_ident()}"
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Request-ID", request_id)
        self.end_headers()
        self.wfile.write(body)

    def require_post(self, method: str) -> bool:
        if method == "POST":
            return True
        self.send_json({"ok": False, "error": "method not allowed"}, HTTPStatus.METHOD_NOT_ALLOWED)
        return False

    def dispatch_api(self, method: str, path: str, query: dict[str, list[str]], body: str) -> None:
        try:
            self.handle_api(method, path, query, body)
        except (BrokenPipeError, ConnectionResetError):
            raise
        except Exception as error:  # Preview must return JSON even when a mock handler has a bug.
            STATE.add_log(
                "ERROR",
                "request.failed",
                "预览 API 请求异常退出",
                method=method,
                path=path,
                error_type=type(error).__name__,
                error=str(error),
            )
            self.send_json(
                {
                    "ok": False,
                    "error": "preview API request failed",
                    "detail": f"{type(error).__name__}: {error}",
                },
                HTTPStatus.INTERNAL_SERVER_ERROR,
            )

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self.send_response(HTTPStatus.FOUND)
            self.send_header("Location", STATIC_BASE)
            self.end_headers()
            return
        if parsed.path.startswith(API_BASE):
            self.dispatch_api("GET", parsed.path[len(API_BASE) :] or "/", parse_qs(parsed.query), "")
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
        try:
            requested_length = int(self.headers.get("Content-Length", "0") or 0)
        except ValueError:
            self.send_json({"ok": False, "error": "invalid content length"}, HTTPStatus.BAD_REQUEST)
            return
        if requested_length < 0 or requested_length > 65536:
            self.send_json({"ok": False, "error": "request body too large"}, HTTPStatus.REQUEST_ENTITY_TOO_LARGE)
            return
        length = requested_length
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        self.dispatch_api("POST", parsed.path[len(API_BASE) :] or "/", parse_qs(parsed.query), body)

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
        if method != "GET" or STATE.log_level == "debug":
            STATE.add_log("INFO" if method != "GET" else "DEBUG", "request.start", "收到预览 API 请求", method=method, path=path)
        if path == "/hardware/diagnostics":
            if method != "GET":
                self.send_json({"ok": False, "error": "method not allowed"}, HTTPStatus.METHOD_NOT_ALLOWED)
                return
            stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(now))
            content = "\n".join([
                "UGREEN LED diagnostic bundle",
                "bundle_version=1",
                "collector_exit_code=0",
                "",
                "===== hardware-diagnostics =====",
                "collector_version=1",
                "read_only=true",
                "product_name=DXP480T Plus",
                "it87_loaded=true",
                "it87_bound=true",
                "",
                "===== application-log-tail =====",
                *list(STATE.logs)[-20:],
            ])
            self.send_json({
                "ok": True,
                "filename": f"ugreen-led-diagnostics-{stamp}.txt",
                "size_bytes": len(content.encode("utf-8")),
                "collector_exit_code": 0,
                "clipped": False,
                "content": content,
            })
            return
        if path == "/logs":
            if method != "GET":
                self.send_json({"ok": False, "error": "method not allowed"}, HTTPStatus.METHOD_NOT_ALLOWED)
                return
            source = (query.get("source") or ["application"])[0]
            level = (query.get("level") or ["all"])[0].lower()
            try:
                line_limit = max(20, min(1000, int((query.get("lines") or ["300"])[0])))
            except ValueError:
                line_limit = 300
            if source != "application":
                self.send_json({"ok": False, "error": "unknown log source"})
                return
            with STATE.lock:
                entries = list(STATE.logs)
                write_level = STATE.log_level
            if level in {"debug", "info", "warn", "error"}:
                marker = f"[{level.upper()}]"
                entries = [entry for entry in entries if marker in entry]
            else:
                level = "all"
            content = "\n".join(entries[-line_limit:])
            self.send_json({
                "ok": True,
                "source": "application",
                "level": level,
                "requested_lines": line_limit,
                "size_bytes": len("\n".join(entries).encode("utf-8")),
                "updated_at": int(now),
                "clipped": False,
                "write_level": write_level,
                "content": content,
            })
            return
        if path == "/logs/config":
            level = (query.get("level") or [""])[0].lower()
            if method != "POST":
                self.send_json({"ok": False, "error": "method not allowed"}, HTTPStatus.METHOD_NOT_ALLOWED)
                return
            if level not in {"debug", "info", "warn", "error"}:
                self.send_json({"ok": False, "error": "invalid log level"})
                return
            with STATE.lock:
                STATE.log_level = level
            STATE.add_log("INFO", "logging.level_changed", "日志记录级别已更新", write_level=level)
            self.send_json({"ok": True, "level": level, "message": f"日志记录级别已切换为 {level.upper()}"})
            return
        if path == "/logs/clear":
            if not self.require_post(method):
                return
            if (query.get("confirm") or [""])[0] != "clear-logs":
                self.send_json({"ok": False, "error": "log clear confirmation required"})
                return
            with STATE.lock:
                STATE.logs.clear()
            STATE.add_log("INFO", "logging.cleared", "应用诊断日志已清空")
            self.send_json({"ok": True, "message": "应用诊断日志已清空"})
            return
        if path == "/logs/client":
            if method != "POST":
                self.send_json({"ok": False, "error": "method not allowed"}, HTTPStatus.METHOD_NOT_ALLOWED)
                return
            if len(body.encode("utf-8")) > 8192:
                self.send_json({"ok": False, "error": "client log payload too large"}, HTTPStatus.REQUEST_ENTITY_TOO_LARGE)
                return
            try:
                client_error = json.loads(body or "{}")
            except json.JSONDecodeError:
                client_error = {"message": "invalid client error payload"}
            if not isinstance(client_error, dict):
                client_error = {"message": "invalid client error payload"}
            STATE.add_log(
                "WARN",
                "client.error",
                str(client_error.get("message") or "Web 前端运行时错误")[:600],
                kind=str(client_error.get("kind") or "runtime")[:40],
                route=str(client_error.get("route") or "unknown")[:80],
                related_request_id=str(client_error.get("related_request_id") or "")[:64],
            )
            self.send_json({"ok": True})
            return
        if path == "/status":
            rx = int(1150 + abs(math.sin(now / 4.2)) * 9800)
            tx = int(380 + abs(math.cos(now / 5.1)) * 2400)
            power_only = STATE.selected_profile() == "dxp480t_plus"
            power26 = STATE.settings.setdefault("power26", OrderedDict())
            power26_color = power26.get("color", "white").upper()
            power26_effect = power26.get("effect", "steady")
            power26_status = "power: off" if STATE.mode == "off" else f"power: on  {power26_color}  mode={power26_effect}"
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
                "led_status": power26_status if power_only else "power: on  RGB(100,100,100)  brightness=40\nnetdev: blink  RGB(160,0,255)  brightness=64\ndisk1: on  RGB(0,255,0)  brightness=128\ndisk2: on  RGB(255,255,0)  brightness=64\ndisk3: standby  RGB(0,100,255)  brightness=40",
            })
            return
        if path == "/mapping":
            disk_count = STATE.profile_meta()[2]
            states = ["active", "idle", "standby", "idle", "deep_sleep", "active"]
            speeds = [
                (disk["device"], STATE.active_led_map().get(disk["device"], ""), states[index],
                 int(abs(math.sin(now / (2.5 + index))) * (3500 if index in {0, 5} else 80)),
                 int(abs(math.cos(now / (3.2 + index))) * (880 if index in {0, 5} else 35)))
                for index, disk in enumerate(STATE.lab_disks[:disk_count])
                if disk["device"] in STATE.active_led_map()
            ]
            self.send_json({"ok": True, "mapping": [
                {"device": dev, "led": led, "state": state, "read_kbps": read, "write_kbps": write, "total_kbps": read + write, "updated_at": int(now)}
                for dev, led, state, read, write in speeds
            ]})
            return
        if path == "/settings":
            if method == "POST":
                try:
                    STATE.update_settings(body)
                except ValueError as error:
                    self.send_json({"ok": False, "error": str(error)}, HTTPStatus.BAD_REQUEST)
                    return
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
                profile_name, support, disk_count, netdev_count, driver_supported = PROFILE_META.get(
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
                "product_name": f"{profile_name}（预览）",
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
                "it87_loaded": False,
                "led_plugin_conflict": False,
                "led_plugin_modules": "",
                "dkms_installed": STATE.driver_loaded,
                "dkms_registered": STATE.driver_loaded,
                "driver_managed": STATE.driver_loaded,
                "driver_supported": driver_supported,
                "kernel": "6.12.0-preview",
                "system_hostname": "dxp480tplus-preview" if selected_profile == "dxp480t_plus" else "dxp4800s-preview" if selected_profile == "dxp4800s" else "dxp4800plus-preview",
                "system_os": "fnOS 1.1（预览）",
                "system_uptime_seconds": 345678,
                "system_cpu_model": "Intel(R) Pentium(R) Gold 8505",
                "system_cpu_threads": 6,
                "system_load_1": 0.18,
                "system_load_5": 0.24,
                "system_load_15": 0.21,
                "system_memory_total_mb": 8192,
                "system_memory_used_mb": 3379,
                "system_memory_percent": 41,
                "system_cpu_temp_c": 47.2,
            })
            return
        if path == "/bios/status":
            self.send_json(STATE.bios_payload())
            return
        if path == "/bios/fan":
            channel = (query.get("channel") or [""])[0]
            profile = STATE.selected_profile()
            is_480t = profile == "dxp480t_plus"
            is_4800s = profile == "dxp4800s"
            is_6800 = profile == "dxp6800"
            try:
                pwm = int((query.get("pwm") or ["-1"])[0])
            except ValueError:
                pwm = -1
            if method != "POST":
                self.send_json({"ok": False, "error": "method not allowed"}, HTTPStatus.METHOD_NOT_ALLOWED)
                return
            if profile not in {"dxp4800_plus", "dxp4800_pro", "dxp4800s", "dxp480t_plus", "dxp6800"}:
                self.send_json({"ok": False, "error": "BIOS 控制仅支持 DXP4800 Plus / Pro、DXP4800S、DXP480T Plus 与 DXP6800 Pro"})
                return
            if (is_4800s or is_6800) and (query.get("confirm") or [""])[0] != "firmware-reversed":
                self.send_json({"ok": False, "error": "固件逆向写入尚未实机验证，请先确认风险"})
                return
            valid_channels = {"sys"} if is_4800s else {"cpu", "all"} if is_480t else {"cpu", "sys"}
            minimum = 64 if is_4800s else 40
            if channel not in valid_channels or not minimum <= pwm <= 255:
                self.send_json({"ok": False, "error": "风扇参数无效"})
                return
            with STATE.lock:
                if channel in {"cpu", "all"}:
                    STATE.bios_cpu_pwm = pwm
                    STATE.bios_cpu_manual = True
                if channel == "sys":
                    STATE.bios_sys_pwm = pwm
                    STATE.bios_sys_manual = True
                    if is_6800:
                        STATE.bios_sys2_pwm = pwm
                        STATE.bios_sys2_manual = True
                if channel == "all":
                    STATE.bios_sys_pwm = pwm
                    STATE.bios_sys2_pwm = pwm
                    STATE.bios_sys_manual = True
                    STATE.bios_sys2_manual = True
            fan_name = "全部风扇" if channel == "all" else "CPU 风扇" if channel == "cpu" else "系统风扇"
            self.send_json(STATE.bios_payload(f"{fan_name} PWM 已设置为 {pwm}"))
            return
        if path == "/bios/fan/mode":
            channel = (query.get("channel") or [""])[0]
            fan_mode = (query.get("mode") or [""])[0]
            profile = STATE.selected_profile()
            is_480t = profile == "dxp480t_plus"
            if method != "POST":
                self.send_json({"ok": False, "error": "method not allowed"}, HTTPStatus.METHOD_NOT_ALLOWED)
                return
            if profile not in {"dxp4800_plus", "dxp4800_pro", "dxp4800s", "dxp480t_plus", "dxp6800"}:
                self.send_json({"ok": False, "error": "BIOS 控制仅支持 DXP4800 Plus / Pro、DXP4800S、DXP480T Plus 与 DXP6800 Pro"})
                return
            if profile == "dxp4800s":
                self.send_json({"ok": False, "error": "DXP4800S 当前模式不可读，只开放受保护的手动 PWM 写入"})
                return
            valid_channels = {"cpu", "all"} if is_480t else {"cpu", "sys"}
            if channel not in valid_channels or fan_mode not in {"auto", "manual"}:
                self.send_json({"ok": False, "error": "风扇模式参数无效"})
                return
            manual = fan_mode == "manual"
            with STATE.lock:
                if manual:
                    current_pwms = [STATE.bios_cpu_pwm]
                    if channel == "sys":
                        current_pwms = [STATE.bios_sys_pwm]
                    elif channel == "all":
                        current_pwms = [STATE.bios_cpu_pwm, STATE.bios_sys2_pwm, STATE.bios_sys_pwm]
                    if any(pwm < 40 for pwm in current_pwms):
                        self.send_json({"ok": False, "error": "当前 PWM 低于 40，拒绝进入手动模式"})
                        return
                if channel in {"cpu", "all"}:
                    STATE.bios_cpu_manual = manual
                if channel in {"sys", "all"}:
                    STATE.bios_sys_manual = manual
                if channel == "all":
                    STATE.bios_sys2_manual = manual
            fan_name = "全部风扇" if channel == "all" else "CPU 风扇" if channel == "cpu" else "系统风扇"
            message = f"{fan_name} 已切换到手动 PWM 模式" if manual else f"{fan_name} 已恢复硬件自动调速"
            self.send_json(STATE.bios_payload(message))
            return
        if path == "/bios/startup":
            policy = (query.get("policy") or [""])[0]
            profile = STATE.selected_profile()
            if method != "POST":
                self.send_json({"ok": False, "error": "method not allowed"}, HTTPStatus.METHOD_NOT_ALLOWED)
                return
            if profile not in {"dxp4800_plus", "dxp4800_pro", "dxp4800s", "dxp480t_plus", "dxp6800"}:
                self.send_json({"ok": False, "error": "BIOS 控制仅支持 DXP4800 Plus / Pro、DXP4800S、DXP480T Plus 与 DXP6800 Pro"})
                return
            if profile in {"dxp4800s", "dxp6800"} and (query.get("confirm") or [""])[0] != "firmware-reversed":
                self.send_json({"ok": False, "error": "固件逆向写入尚未实机验证，请先确认风险"})
                return
            if policy not in {"on", "off", "last"}:
                self.send_json({"ok": False, "error": "来电启动参数无效"})
                return
            with STATE.lock:
                STATE.bios_startup = policy
            self.send_json(STATE.bios_payload("来电启动策略已更新"))
            return
        if path == "/power26/apply":
            color = (query.get("color") or [""])[0]
            effect = (query.get("effect") or [""])[0]
            try:
                threshold = int((query.get("threshold") or ["32"])[0])
            except ValueError:
                threshold = 0
            if method != "POST":
                self.send_json({"ok": False, "error": "method not allowed"}, HTTPStatus.METHOD_NOT_ALLOWED)
                return
            if STATE.selected_profile() != "dxp480t_plus":
                self.send_json({"ok": False, "error": "current model does not use the power-0x26 backend"})
                return
            if color not in {"red", "white"} or effect not in {"steady", "fast", "slow", "breath", "network", "off"} or not 1 <= threshold <= 1048576:
                self.send_json({"ok": False, "error": "invalid power light parameters"})
                return
            with STATE.lock:
                power26 = STATE.settings.setdefault("power26", OrderedDict())
                power26["color"] = color
                if effect == "off":
                    STATE.settings.setdefault("mode", OrderedDict())["global"] = "off"
                    mode = "off"
                else:
                    power26["effect"] = effect
                    power26["network_threshold_kbps"] = str(threshold)
                    mode = "smart" if effect == "network" else "on"
                    STATE.settings.setdefault("mode", OrderedDict())["global"] = mode
            self.send_json({
                "ok": True,
                "mode": mode,
                "color": color,
                "effect": effect,
                "message": "电源灯已关闭" if effect == "off" else "480T 电源灯设置已应用",
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
            if not self.require_post(method):
                return
            if (query.get("confirm") or [""])[0] != "install-driver":
                self.send_json({"ok": False, "error": "driver confirmation required"})
                return
            with STATE.lock:
                STATE.driver_loaded = True
                STATE.settings.setdefault("hardware", OrderedDict())["backend"] = "sysfs"
            self.send_json({"ok": True, "message": "内核驱动已安装并切换到 sysfs 后端"})
            return
        if path == "/driver/unload":
            if not self.require_post(method):
                return
            if (query.get("confirm") or [""])[0] != "unload-driver":
                self.send_json({"ok": False, "error": "driver confirmation required"})
                return
            with STATE.lock:
                STATE.driver_loaded = False
                STATE.settings.setdefault("hardware", OrderedDict())["backend"] = "cli"
            self.send_json({"ok": True, "message": "内核驱动已卸载，已切换到 CLI 后端"})
            return
        if path == "/lab/mapping/start":
            if not self.require_post(method):
                return
            with STATE.lock:
                STATE.lab_active = True
                STATE.lab_highlight = ""
            self.send_json(STATE.lab_payload("检测模式已启动，全部硬盘灯已点亮"))
            return
        if path == "/lab/mapping/highlight":
            if not self.require_post(method):
                return
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
            if not self.require_post(method):
                return
            if not STATE.lab_active:
                self.send_json({"ok": False, "error": "检测会话已结束，请重新开始"})
                return
            try:
                STATE.save_identity_mapping(body)
            except (ValueError, TypeError) as error:
                self.send_json({"ok": False, "error": str(error)})
                return
            self.send_json(STATE.lab_payload("按硬盘绑定已保存"))
            return
        if path == "/lab/position/save":
            if not self.require_post(method):
                return
            if not STATE.lab_active:
                self.send_json({"ok": False, "error": "检测会话已结束，请重新开始"})
                return
            try:
                STATE.save_position_mapping(body)
            except (ValueError, TypeError) as error:
                self.send_json({"ok": False, "error": str(error)})
                return
            self.send_json(STATE.lab_payload("灯光与硬盘位置绑定已保存"))
            return
        if path == "/lab/mapping/cancel":
            if not self.require_post(method):
                return
            with STATE.lock:
                STATE.lab_active = False
                STATE.lab_highlight = ""
            self.send_json(STATE.lab_payload("已退出检测模式，原映射保持不变"))
            return
        if path == "/lab/mapping/reset":
            if not self.require_post(method):
                return
            STATE.reset_lab_mapping()
            self.send_json(STATE.lab_payload("已恢复自动 HCTL 映射"))
            return
        if path == "/mode":
            if not self.require_post(method):
                return
            mode = (query.get("mode") or [""])[0]
            if mode not in {"off", "on", "smart"}:
                self.send_json({"ok": False, "error": "invalid mode"})
                return
            STATE.set_mode(mode)
            self.send_json({"ok": True, "mode": STATE.mode})
            return
        if path == "/remap":
            if not self.require_post(method):
                return
            STATE.remap_count += 1
            STATE.reset_lab_mapping()
            disk_count = STATE.profile_meta()[2]
            self.send_json({"ok": True, "message": f"已重新检测 {disk_count} 块硬盘", "disk_count": disk_count})
            return
        if path == "/daemon/start":
            if not self.require_post(method):
                return
            STATE.daemon = "running"
            self.send_json({"ok": True, "daemon": STATE.daemon, "message": "后台已启动"})
            return
        if path == "/daemon/stop":
            if not self.require_post(method):
                return
            STATE.daemon = "stopped"
            self.send_json({"ok": True, "daemon": STATE.daemon, "message": "后台已停止"})
            return
        self.send_json({"ok": False, "error": "unknown preview route", "path": path}, HTTPStatus.NOT_FOUND)


def main() -> None:
    parser = argparse.ArgumentParser(description="预览绿联 LED 灯控 Web UI")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--profile", choices=sorted(PROFILE_META), default="dxp6800", help="预览指定机型能力")
    parser.add_argument("--no-open", action="store_true", help="不自动打开浏览器")
    args = parser.parse_args()

    STATE.configure_profile(args.profile)

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

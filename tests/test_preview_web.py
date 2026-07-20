#!/usr/bin/env python3
"""Integration tests for the local preview HTTP API."""

from __future__ import annotations

import http.client
import importlib.util
import json
import threading
import unittest
from pathlib import Path
from types import ModuleType
from typing import Callable


ROOT = Path(__file__).resolve().parent.parent
PREVIEW_PATH = ROOT / "scripts" / "preview_web.py"


def load_preview() -> ModuleType:
    spec = importlib.util.spec_from_file_location("llled_preview_web", PREVIEW_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {PREVIEW_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


preview = load_preview()


class QuietPreviewHandler(preview.PreviewHandler):
    def log_message(self, _fmt: str, *_args: object) -> None:
        return


class PreviewApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = preview.ThreadingHTTPServer(("127.0.0.1", 0), QuietPreviewHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.host, cls.port = cls.server.server_address

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)

    def setUp(self) -> None:
        preview.STATE = preview.PreviewState()

    def request(
        self,
        method: str,
        route: str,
        body: str = "",
        request_id: str = "preview-test-request",
    ) -> tuple[int, dict[str, object], dict[str, str]]:
        connection = http.client.HTTPConnection(self.host, self.port, timeout=5)
        payload = body.encode("utf-8")
        headers = {
            "Content-Length": str(len(payload)),
            "Content-Type": "text/plain; charset=utf-8",
            "X-Request-ID": request_id,
        }
        try:
            connection.request(method, f"{preview.API_BASE}{route}", body=payload, headers=headers)
            response = connection.getresponse()
            raw = response.read().decode("utf-8")
            response_headers = {key.lower(): value for key, value in response.getheaders()}
            return response.status, json.loads(raw), response_headers
        finally:
            connection.close()

    def state_snapshot(self) -> tuple[object, ...]:
        state = preview.STATE
        with state.lock:
            return (
                preview.dump_ini(state.settings),
                state.daemon,
                state.remap_count,
                state.lab_active,
                state.lab_highlight,
                state.driver_loaded,
                state.bios_cpu_pwm,
                state.bios_sys_pwm,
                state.bios_sys2_pwm,
                state.bios_startup,
                tuple(state.logs),
            )

    def test_mutating_routes_reject_get_without_changing_state(self) -> None:
        routes = [
            "/logs/config?level=debug",
            "/logs/clear?confirm=clear-logs",
            "/logs/client",
            "/bios/fan?channel=cpu&pwm=120",
            "/bios/fan/mode?channel=cpu&mode=manual",
            "/bios/startup?policy=on",
            "/power26/apply?color=white&effect=steady&threshold=32",
            "/driver/install?confirm=install-driver",
            "/driver/unload?confirm=unload-driver",
            "/lab/mapping/start",
            "/lab/mapping/highlight?led=disk1",
            "/lab/mapping/save",
            "/lab/position/save",
            "/lab/mapping/cancel",
            "/lab/mapping/reset",
            "/mode?mode=off",
            "/remap",
            "/daemon/start",
            "/daemon/stop",
        ]
        for route in routes:
            with self.subTest(route=route):
                preview.STATE = preview.PreviewState()
                before = self.state_snapshot()
                status, payload, headers = self.request("GET", route)
                self.assertEqual(status, 405)
                self.assertEqual(payload, {"ok": False, "error": "method not allowed"})
                self.assertTrue(headers["content-type"].startswith("application/json"))
                self.assertEqual(headers["x-request-id"], "preview-test-request")
                self.assertEqual(self.state_snapshot(), before)

    def test_driver_changes_require_confirmation(self) -> None:
        status, payload, _ = self.request("POST", "/driver/install")
        self.assertEqual(status, 200)
        self.assertFalse(payload["ok"])
        self.assertFalse(preview.STATE.driver_loaded)

        status, payload, _ = self.request("POST", "/driver/install?confirm=install-driver")
        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertTrue(preview.STATE.driver_loaded)

        status, payload, _ = self.request("POST", "/driver/unload")
        self.assertEqual(status, 200)
        self.assertFalse(payload["ok"])
        self.assertTrue(preview.STATE.driver_loaded)

        status, payload, _ = self.request("POST", "/driver/unload?confirm=unload-driver")
        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertFalse(preview.STATE.driver_loaded)

    def test_hardware_diagnostics_download_payload(self) -> None:
        status, payload, headers = self.request("GET", "/hardware/diagnostics")
        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertTrue(str(payload["filename"]).startswith("ugreen-led-diagnostics-"))
        self.assertIn("===== hardware-diagnostics =====", payload["content"])
        self.assertIn("collector_version=1", payload["content"])
        self.assertIn("===== application-log-tail =====", payload["content"])
        self.assertTrue(headers["content-type"].startswith("application/json"))

    def test_invalid_settings_are_rejected_atomically(self) -> None:
        original = preview.dump_ini(preview.STATE.settings)
        status, payload, _ = self.request(
            "POST",
            "/settings",
            "mode.global=off\nthis line is invalid\nhardware.backend=cli",
        )
        self.assertEqual(status, 400)
        self.assertEqual(payload, {"ok": False, "error": "invalid settings payload"})
        self.assertEqual(preview.dump_ini(preview.STATE.settings), original)

        status, payload, _ = self.request(
            "POST",
            "/settings",
            "# preview update\nmode.global=off\nhardware.backend=cli",
        )
        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(preview.STATE.mode, "off")
        self.assertEqual(preview.STATE.settings["hardware"]["backend"], "cli")

    def test_invalid_mode_does_not_report_success_or_mutate(self) -> None:
        original_mode = preview.STATE.mode
        status, payload, _ = self.request("POST", "/mode?mode=unexpected")
        self.assertEqual(status, 200)
        self.assertEqual(payload, {"ok": False, "error": "invalid mode"})
        self.assertEqual(preview.STATE.mode, original_mode)

    def test_dxp6800_bios_pair_requires_firmware_reversed_confirmation(self) -> None:
        preview.STATE.configure_profile("dxp6800")

        status, payload, _ = self.request("GET", "/bios/status")
        self.assertEqual(status, 200)
        self.assertTrue(payload["supported"])
        self.assertEqual(payload["model"], "dxp6800pro")
        self.assertTrue(payload["write_confirmation_required"])
        self.assertFalse(payload["fan_mode_writable"])
        self.assertEqual(payload["sys2_rpm"], 820)

        original_pair = (preview.STATE.bios_sys_pwm, preview.STATE.bios_sys2_pwm)
        status, payload, _ = self.request("POST", "/bios/fan?channel=sys&pwm=120")
        self.assertEqual(status, 200)
        self.assertFalse(payload["ok"])
        self.assertEqual((preview.STATE.bios_sys_pwm, preview.STATE.bios_sys2_pwm), original_pair)

        status, payload, _ = self.request(
            "POST", "/bios/fan?channel=sys&pwm=120&confirm=firmware-reversed"
        )
        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual((preview.STATE.bios_sys_pwm, preview.STATE.bios_sys2_pwm), (120, 120))

        status, payload, _ = self.request(
            "POST", "/bios/fan?channel=sys1&pwm=120&confirm=firmware-reversed"
        )
        self.assertEqual(status, 200)
        self.assertFalse(payload["ok"])

        status, payload, _ = self.request("POST", "/bios/startup?policy=off")
        self.assertEqual(status, 200)
        self.assertFalse(payload["ok"])
        self.assertNotEqual(preview.STATE.bios_startup, "off")

        status, payload, _ = self.request(
            "POST", "/bios/startup?policy=off&confirm=firmware-reversed"
        )
        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(preview.STATE.bios_startup, "off")

    def test_bios_telemetry_returns_time_samples_for_each_window(self) -> None:
        preview.STATE.configure_profile("dxp6800")
        expected_minimums = {"1m": 3, "1h": 121, "24h": 2881}
        for range_name, minimum in expected_minimums.items():
            with self.subTest(range_name=range_name):
                status, payload, _ = self.request("GET", f"/bios/telemetry?range={range_name}")
                self.assertEqual(status, 200)
                self.assertTrue(payload["ok"])
                self.assertEqual(payload["range"], range_name)
                self.assertEqual(payload["sample_interval_seconds"], 30)
                self.assertGreaterEqual(len(payload["history"]), minimum)
                self.assertLessEqual(payload["history"][0]["at"], payload["history"][-1]["at"])
                self.assertIn("cpuRpm", payload["current"])

        status, payload, _ = self.request("GET", "/bios/telemetry?range=bad")
        self.assertEqual(status, 200)
        self.assertEqual(payload, {"ok": False, "error": "invalid telemetry range"})

    def test_unhandled_preview_exception_is_json(self) -> None:
        original: Callable[[str], None] = preview.STATE.set_mode

        def fail_mode(_mode: str) -> None:
            raise RuntimeError("simulated preview failure")

        preview.STATE.set_mode = fail_mode
        try:
            status, payload, headers = self.request("POST", "/mode?mode=smart")
        finally:
            preview.STATE.set_mode = original

        self.assertEqual(status, 500)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"], "preview API request failed")
        self.assertIn("RuntimeError: simulated preview failure", payload["detail"])
        self.assertTrue(headers["content-type"].startswith("application/json"))
        self.assertEqual(headers["x-request-id"], "preview-test-request")
        self.assertTrue(any("[event=request.failed]" in line for line in preview.STATE.logs))


if __name__ == "__main__":
    unittest.main(verbosity=2)

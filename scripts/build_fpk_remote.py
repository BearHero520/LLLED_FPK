#!/usr/bin/env python3
"""上传项目到 NAS 并用 fnpack 打包，拉回 fpk"""
import os
import getpass
import hashlib
import shlex
import sys
import time
import zipfile
from pathlib import Path

import paramiko

PROJECT = Path(__file__).resolve().parent.parent / "App.Native.UGreenLED"
LED_BUILD_SCRIPT = Path(__file__).resolve().parent / "build_ugreen_leds_cli.py"
FAN_CURVE_API_TEST = Path(__file__).resolve().parent.parent / "tests" / "test_fan_curve_api.sh"
REMOTE_DIR = "/tmp/App.Native.UGreenLED-build"
LOCAL_ZIP = Path(__file__).resolve().parent / "ugreen_led_pkg.zip"
TEXT_SUFFIX = {".sh", ".cgi", ".conf", ".js", ".css", ".html", ".py"}
TEXT_NAMES = {
    "manifest",
    "main",
    "config",
    "resource",
    "privilege",
    "install_init",
    "install_callback",
    "upgrade_init",
    "upgrade_callback",
    "uninstall_init",
    "uninstall_callback",
    "config_init",
    "config_callback",
}


def run(c, cmd, wait=1.0, stdin_text=None, display_cmd=None, get_pty=False):
    print(">>>", (display_cmd or cmd)[:160])
    stdin, stdout, stderr = c.exec_command(cmd, timeout=120, get_pty=get_pty)
    if stdin_text is not None:
        stdin.write(stdin_text)
        stdin.flush()
        stdin.channel.shutdown_write()
    time.sleep(wait)
    raw = (stdout.read() + stderr.read()).decode(errors="replace")
    exit_status = stdout.channel.recv_exit_status()
    lines = [ln for ln in raw.splitlines() if "password for" not in ln.lower()]
    text = "\n".join(lines)
    if text.strip():
        print(text)
    if exit_status != 0:
        raise RuntimeError(f"remote command failed with exit status {exit_status}")
    return text


def sudo(c, cmd, password, wait=2.0):
    remote_cmd = f"sudo -S -p '' bash -lc {shlex.quote(cmd)}"
    return run(
        c,
        remote_cmd,
        wait,
        stdin_text=password + "\n",
        display_cmd=f"sudo bash -lc {shlex.quote(cmd)}",
    )


def make_zip():
    if LOCAL_ZIP.exists():
        LOCAL_ZIP.unlink()
    with zipfile.ZipFile(LOCAL_ZIP, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(PROJECT):
            dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", "wizard", "scripts"}]
            for name in files:
                if name == ".git":
                    continue
                fp = Path(root) / name
                arc = fp.relative_to(PROJECT).as_posix()
                data = fp.read_bytes()
                if fp.suffix in TEXT_SUFFIX or fp.name in TEXT_NAMES:
                    data = data.replace(b"\r\n", b"\n")
                zf.writestr(arc, data)
        data = LED_BUILD_SCRIPT.read_bytes().replace(b"\r\n", b"\n")
        zf.writestr("scripts/build_ugreen_leds_cli.py", data)
    print(f"ZIP: {LOCAL_ZIP} ({LOCAL_ZIP.stat().st_size} bytes)\n")


def main():
    host = os.environ.get("FNOS_HOST") or input("飞牛 NAS 地址: ").strip()
    user = os.environ.get("FNOS_USER") or input("管理员用户名: ").strip()
    password = os.environ.get("FNOS_PASSWORD") or getpass.getpass("管理员密码: ")
    if not host or not user or not password:
        print("NAS 地址、用户名和密码不能为空")
        sys.exit(2)

    make_zip()
    c = paramiko.SSHClient()
    c.load_system_host_keys()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username=user, password=password, timeout=20)
    sftp = c.open_sftp()

    run(c, f"rm -rf {REMOTE_DIR}")
    run(c, f"mkdir -p {REMOTE_DIR}")
    sftp.put(str(LOCAL_ZIP), "/tmp/ugreen_led_pkg.zip")
    run(c, f"cd {REMOTE_DIR} && unzip -o /tmp/ugreen_led_pkg.zip", 1.5)
    run(c, f"mkdir -p {REMOTE_DIR}/tests")
    sftp.put(str(FAN_CURVE_API_TEST), f"{REMOTE_DIR}/tests/test_fan_curve_api.sh")
    run(
        c,
        f"chmod +x {REMOTE_DIR}/cmd/* {REMOTE_DIR}/app/ui/*.cgi "
        f"{REMOTE_DIR}/app/server/*.sh {REMOTE_DIR}/app/server/lib/*.sh "
        f"{REMOTE_DIR}/tests/test_fan_curve_api.sh 2>/dev/null; true",
    )

    print("\n=== validate fan curve API ===")
    run(c, f"bash {REMOTE_DIR}/tests/test_fan_curve_api.sh")

    print("\n=== build bundled UGREEN-NAS-Hardware control CLI ===")
    sudo(
        c,
        "if ! command -v cmake >/dev/null 2>&1 || ! command -v cc >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then "
        "apt-get update -qq && apt-get install -y -qq cmake build-essential git; fi",
        password,
        5,
    )

    print("\n=== build patched bundled LED CLI ===")
    run(c, f"ln -sfn . {REMOTE_DIR}/App.Native.UGreenLED")
    run(c, f"python3 {REMOTE_DIR}/scripts/build_ugreen_leds_cli.py", 8)
    run(c, f"rm -f {REMOTE_DIR}/App.Native.UGreenLED")

    hardware_source = f"{REMOTE_DIR}/app/server/vendor/UGREEN-NAS-Hardware"
    hardware_build = f"{REMOTE_DIR}/.ugreenctl-build"
    run(
        c,
        f"cmake -S {hardware_source} -B {hardware_build} -DCMAKE_BUILD_TYPE=Release && "
        f"cmake --build {hardware_build} --parallel && "
        f"ctest --test-dir {hardware_build} --output-on-failure && "
        f"model_list=\"$({hardware_build}/ugreenctl --plugin-dir {hardware_build}/models models)\" && "
        f"printf '%s\\n' \"$model_list\" && "
        f"printf '%s\\n' \"$model_list\" | grep -q '^dx4600[[:space:]]' && "
        f"printf '%s\\n' \"$model_list\" | grep -q '^dxp4800[[:space:]]' && "
        f"printf '%s\\n' \"$model_list\" | grep -q '^dxp4800plus[[:space:]]' && "
        f"printf '%s\\n' \"$model_list\" | grep -q '^dxp4800s[[:space:]]' && "
        f"printf '%s\\n' \"$model_list\" | grep -q '^dxp480tplus[[:space:]]' && "
        f"printf '%s\\n' \"$model_list\" | grep -q '^dxp6800pro[[:space:]]' && "
        f"mkdir -p {REMOTE_DIR}/app/server/bin {REMOTE_DIR}/app/server/lib/ugreenctl/models && "
        f"install -m 0755 {hardware_build}/ugreenctl {hardware_build}/ugreenctl-fand "
        f"{REMOTE_DIR}/app/server/bin/ && "
        f"install -m 0644 {hardware_build}/models/dx4600.so {hardware_build}/models/dxp4800.so {hardware_build}/models/dxp4800plus.so {hardware_build}/models/dxp4800s.so "
        f"{hardware_build}/models/dxp480tplus.so {hardware_build}/models/dxp6800pro.so "
        f"{REMOTE_DIR}/app/server/lib/ugreenctl/models/",
        8,
    )

    print("\n=== fnpack build ===")
    sudo(c, f"cd {REMOTE_DIR} && fnpack build", password, 5)

    listing = run(c, f"ls -la {REMOTE_DIR}/*.fpk 2>/dev/null; ls -la {REMOTE_DIR}/", 1)
    fpk_name = None
    for part in listing.replace("\n", " ").split():
        if part.endswith(".fpk"):
            fpk_name = os.path.basename(part)
            break

    if not fpk_name:
        print("打包失败，未生成 fpk")
        sftp.close()
        c.close()
        sys.exit(1)

    remote_fpk = f"{REMOTE_DIR}/{fpk_name}"
    local_fpk = PROJECT.parent / fpk_name
    print("\n=== verify FPK contents ===")
    required_entries = " ".join(
        shlex.quote(entry)
        for entry in (
            "server/bin/ugreenctl",
            "server/bin/ugreenctl-fand",
            "server/lib/ugreenctl/models/dx4600.so",
            "server/lib/ugreenctl/models/dxp4800.so",
            "server/lib/ugreenctl/models/dxp4800plus.so",
            "server/lib/ugreenctl/models/dxp4800s.so",
            "server/lib/ugreenctl/models/dxp480tplus.so",
            "server/lib/ugreenctl/models/dxp6800pro.so",
        )
    )
    run(
        c,
        f"tar -xOf {remote_fpk} manifest | grep -q '^version[[:space:]]*=' && "
        f"for entry in {required_entries}; do "
        f"tar -xOf {remote_fpk} app.tgz | tar -tzf - | grep -qx \"$entry\" || exit 1; "
        f"done && "
        f"! (tar -xOf {remote_fpk} app.tgz | tar -tzf - | grep -q '^tests/') && "
        f"tar -xOf {remote_fpk} app.tgz | tar -xOzf - ui/api.cgi | grep -q '^url_decode()'",
        2,
    )

    print(f"\n下载: {remote_fpk}")
    sftp.get(remote_fpk, str(local_fpk))
    remote_hash = run(c, f"sha256sum {remote_fpk} | awk '{{print $1}}'", 1).strip()
    local_hash = hashlib.sha256(local_fpk.read_bytes()).hexdigest()
    if remote_hash != local_hash:
        raise RuntimeError("downloaded FPK SHA256 does not match remote build output")
    sftp.close()
    c.close()
    print(f"完成: {local_fpk}")
    print(f"大小: {local_fpk.stat().st_size:,} bytes")
    print(f"SHA256: {local_hash}")


if __name__ == "__main__":
    main()

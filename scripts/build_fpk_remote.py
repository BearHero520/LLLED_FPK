#!/usr/bin/env python3
"""上传项目到 NAS 并用 fnpack 打包，拉回 fpk"""
import os
import sys
import time
import zipfile
from pathlib import Path

import paramiko

HOST = "192.168.50.200"
USER = "Hero"
PASSWORD = "1522151116Long"
PROJECT = Path(__file__).resolve().parent.parent / "App.Native.UGreenLED"
REMOTE_DIR = "/tmp/App.Native.UGreenLED-build"
LOCAL_ZIP = Path(__file__).resolve().parent / "ugreen_led_pkg.zip"
TEXT_SUFFIX = {".sh", ".cgi", ".conf"}


def run(c, cmd, wait=1.0):
    print(">>>", cmd[:120])
    _, stdout, stderr = c.exec_command(cmd, timeout=120, get_pty=True)
    time.sleep(wait)
    raw = (stdout.read() + stderr.read()).decode(errors="replace")
    lines = [ln for ln in raw.splitlines() if "password for" not in ln.lower()]
    text = "\n".join(lines)
    if text.strip():
        print(text)
    return text


def sudo(c, cmd, wait=2.0):
    return run(c, f"echo '{PASSWORD}' | sudo -S bash -c {repr(cmd)}", wait)


def make_zip():
    if LOCAL_ZIP.exists():
        LOCAL_ZIP.unlink()
    with zipfile.ZipFile(LOCAL_ZIP, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(PROJECT):
            dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", "wizard", "scripts"}]
            for name in files:
                fp = Path(root) / name
                arc = fp.relative_to(PROJECT).as_posix()
                data = fp.read_bytes()
                if fp.suffix in TEXT_SUFFIX or fp.name == "manifest":
                    data = data.replace(b"\r\n", b"\n")
                zf.writestr(arc, data)
    print(f"ZIP: {LOCAL_ZIP} ({LOCAL_ZIP.stat().st_size} bytes)\n")


def main():
    make_zip()
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username=USER, password=PASSWORD, timeout=20)
    sftp = c.open_sftp()

    run(c, f"rm -rf {REMOTE_DIR}")
    run(c, f"mkdir -p {REMOTE_DIR}")
    sftp.put(str(LOCAL_ZIP), "/tmp/ugreen_led_pkg.zip")
    run(c, f"cd {REMOTE_DIR} && unzip -o /tmp/ugreen_led_pkg.zip", 1.5)
    run(
        c,
        f"chmod +x {REMOTE_DIR}/cmd/* {REMOTE_DIR}/app/ui/*.cgi "
        f"{REMOTE_DIR}/app/server/*.sh {REMOTE_DIR}/app/server/lib/*.sh 2>/dev/null; true",
    )

    print("\n=== fnpack build ===")
    sudo(c, f"cd {REMOTE_DIR} && fnpack build", 5)

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
    print(f"\n下载: {remote_fpk}")
    sftp.get(remote_fpk, str(local_fpk))
    sftp.close()
    c.close()
    print(f"完成: {local_fpk}")
    print(f"大小: {local_fpk.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build the patched x86-64 Linux LED CLI bundled in the fnOS FPK."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "App.Native.UGreenLED"
VENDOR = PROJECT / "app" / "server" / "vendor" / "ugreen_leds_controller"
PATCH = VENDOR / "patches" / "dxp480t-power.patch"
UPSTREAM_REPOSITORY = "https://github.com/miskcoo/ugreen_leds_controller.git"
UPSTREAM_COMMIT = "1e881da8b3d8598abadb50e859e8433c365c2840"
DEFAULT_BINARY = PROJECT / "app" / "server" / "bin" / "ugreen_leds_cli"
DEFAULT_HASH_FILE = DEFAULT_BINARY.with_name(f"{DEFAULT_BINARY.name}.sha256")
SOURCES = (
    "cli/i2c.cpp",
    "cli/ugreen_leds.cpp",
    "cli/dxp480t_power.cpp",
    "cli/ugreen_leds_cli.cpp",
)


def run(command: list[str], *, cwd: Path | None = None) -> None:
    print("+", " ".join(command))
    subprocess.run(command, cwd=cwd, check=True)


def require_source_metadata() -> None:
    if not PATCH.is_file():
        raise SystemExit(f"Missing LED CLI patch: {PATCH}")
    if "DXP480T" not in PATCH.read_text(encoding="utf-8"):
        raise SystemExit("The LED CLI patch does not contain the DXP480T implementation")


def checkout_upstream(source: Path) -> None:
    run(["git", "init", "--quiet", str(source)])
    run(["git", "-C", str(source), "remote", "add", "origin", UPSTREAM_REPOSITORY])
    run(["git", "-C", str(source), "fetch", "--depth", "1", "origin", UPSTREAM_COMMIT])
    run(["git", "-C", str(source), "checkout", "--detach", "--quiet", "FETCH_HEAD"])
    resolved = subprocess.run(
        ["git", "-C", str(source), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if resolved != UPSTREAM_COMMIT:
        raise SystemExit(f"Unexpected upstream revision: {resolved}")
    run(["git", "-C", str(source), "apply", "--check", str(PATCH)])
    run(["git", "-C", str(source), "apply", str(PATCH)])


def compiler_command(*, zig: Path | None) -> list[str]:
    if zig is not None:
        if not zig.is_file():
            raise SystemExit(f"Zig compiler was not found: {zig}")
        return [str(zig), "c++", "-target", "x86_64-linux-musl"]
    if os.name == "nt":
        raise SystemExit(
            "A Linux compiler is required on Windows. Pass --zig PATH_TO_ZIG_EXE "
            "or run this script in CI/Linux."
        )
    compiler = shutil.which("g++")
    if compiler is None:
        raise SystemExit("g++ is required to build the bundled LED CLI")
    return [compiler]


def build(*, binary: Path, hash_file: Path, zig: Path | None) -> None:
    require_source_metadata()
    with tempfile.TemporaryDirectory(prefix="ugreen-leds-cli-") as temporary:
        source = Path(temporary) / "source"
        checkout_upstream(source)
        built = Path(temporary) / "ugreen_leds_cli"
        command = compiler_command(zig=zig)
        command.extend(
            [
                "-std=c++17",
                "-O2",
                "-Wall",
                "-static",
                "-I",
                str(source / "cli"),
                *(str(source / path) for path in SOURCES),
                "-o",
                str(built),
            ]
        )
        run(command)
        content = built.read_bytes()
        if content[:4] != b"\x7fELF":
            raise SystemExit("LED CLI build did not produce an ELF executable")

        binary.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(built, binary)
        binary.chmod(0o755)

    digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    hash_file.write_text(f"{digest}  {binary.name}\n", encoding="ascii", newline="\n")
    print(f"Built patched LED CLI: {binary}")
    print(f"SHA256 manifest: {hash_file}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY)
    parser.add_argument("--hash-file", type=Path, default=DEFAULT_HASH_FILE)
    parser.add_argument("--zig", type=Path, help="Path to zig.exe when cross-compiling on Windows")
    args = parser.parse_args()
    build(
        binary=args.binary.resolve(),
        hash_file=args.hash_file.resolve(),
        zig=args.zig.resolve() if args.zig else None,
    )


if __name__ == "__main__":
    main()

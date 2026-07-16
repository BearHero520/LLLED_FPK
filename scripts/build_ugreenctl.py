#!/usr/bin/env python3
"""Build the pinned UGREEN-NAS-Hardware CLI for the fnOS FPK."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = ROOT / "App.Native.UGreenLED" / "app" / "server" / "vendor" / "UGREEN-NAS-Hardware"
DEFAULT_BINARY = ROOT / "App.Native.UGreenLED" / "app" / "server" / "bin" / "ugreenctl"
DEFAULT_PLUGIN_DIR = ROOT / "App.Native.UGreenLED" / "app" / "server" / "lib" / "ugreenctl" / "models"
MODELS = ("dxp4800plus", "dxp480tplus")


def run(command: list[str]) -> None:
    print("+", " ".join(command))
    subprocess.run(command, check=True)


def build(source: Path, binary: Path, plugin_dir: Path) -> None:
    if not (source / "CMakeLists.txt").is_file():
        raise SystemExit(f"UGREEN-NAS-Hardware source is missing: {source}")
    if os.name == "nt":
        raise SystemExit("ugreenctl must be built on x86 Linux; use GitHub Actions for Windows-hosted checkouts")

    with tempfile.TemporaryDirectory(prefix="ugreenctl-build-") as temporary:
        build_dir = Path(temporary) / "build"
        run(["cmake", "-S", str(source), "-B", str(build_dir), "-DCMAKE_BUILD_TYPE=Release"])
        run(["cmake", "--build", str(build_dir), "--parallel"])
        run(["ctest", "--test-dir", str(build_dir), "--output-on-failure"])

        source_binary = build_dir / "ugreenctl"
        if not source_binary.is_file():
            raise SystemExit("UGREEN-NAS-Hardware build did not produce ugreenctl")
        binary.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_binary, binary)
        binary.chmod(0o755)

        plugin_dir.mkdir(parents=True, exist_ok=True)
        for model in MODELS:
            source_plugin = build_dir / "models" / f"{model}.so"
            if not source_plugin.is_file():
                raise SystemExit(f"UGREEN-NAS-Hardware build did not produce {model}.so")
            shutil.copy2(source_plugin, plugin_dir / source_plugin.name)

    print(f"Built ugreenctl: {binary}")
    print(f"Model plugins: {plugin_dir}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY)
    parser.add_argument("--plugin-dir", type=Path, default=DEFAULT_PLUGIN_DIR)
    args = parser.parse_args()
    build(args.source.resolve(), args.binary.resolve(), args.plugin_dir.resolve())


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""在任意 Python 3 环境中构建兼容 fnOS 的 FPK 安装包。"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import os
import re
import shutil
import tarfile
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "App.Native.UGreenLED"
APP_NAME = "App.Native.UGreenLED"
TEXT_SUFFIXES = {".cgi", ".conf", ".css", ".html", ".js", ".md", ".py", ".sh"}
TEXT_NAMES = {
    "config",
    "manifest",
    "privilege",
    "resource",
    "config_callback",
    "config_init",
    "install_callback",
    "install_init",
    "main",
    "uninstall_callback",
    "uninstall_init",
    "upgrade_callback",
    "upgrade_init",
}


def source_epoch() -> int:
    raw = os.environ.get("SOURCE_DATE_EPOCH", "0")
    try:
        return max(0, int(raw))
    except ValueError as exc:
        raise SystemExit("SOURCE_DATE_EPOCH 必须是整数") from exc


def normalized_bytes(path: Path) -> bytes:
    data = path.read_bytes()
    if path.suffix.lower() in TEXT_SUFFIXES or path.name in TEXT_NAMES:
        data = data.replace(b"\r\n", b"\n")
    return data


def add_bytes(
    archive: tarfile.TarFile,
    arcname: str,
    data: bytes,
    *,
    mode: int,
    epoch: int,
) -> None:
    info = tarfile.TarInfo(arcname)
    info.size = len(data)
    info.mode = mode
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "root"
    info.mtime = epoch
    archive.addfile(info, io.BytesIO(data))


def add_directory(archive: tarfile.TarFile, arcname: str, *, epoch: int) -> None:
    info = tarfile.TarInfo(arcname.rstrip("/") + "/")
    info.type = tarfile.DIRTYPE
    info.mode = 0o755
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "root"
    info.mtime = epoch
    archive.addfile(info)


def is_executable(relative: Path, *, command_tree: bool) -> bool:
    if command_tree:
        return True
    return relative.suffix.lower() in {".cgi", ".sh"}


def add_tree(
    archive: tarfile.TarFile,
    source: Path,
    *,
    prefix: str = "",
    command_tree: bool = False,
    epoch: int,
) -> None:
    for path in sorted(source.rglob("*"), key=lambda item: item.as_posix()):
        relative = path.relative_to(source)
        arcname = "/".join(part for part in (prefix, relative.as_posix()) if part)
        if path.is_symlink():
            raise SystemExit(f"暂不支持符号链接：{path}")
        if path.is_dir():
            add_directory(archive, arcname, epoch=epoch)
            continue
        mode = 0o711 if is_executable(relative, command_tree=command_tree) else 0o600
        add_bytes(archive, arcname, normalized_bytes(path), mode=mode, epoch=epoch)


def write_gzip_tar(path: Path, writer, *, epoch: int) -> None:
    with path.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=epoch) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.GNU_FORMAT) as archive:
                writer(archive)


def read_version(manifest: bytes) -> str:
    match = re.search(rb"(?m)^version\s*=\s*([^\s]+)\s*$", manifest)
    if not match:
        raise SystemExit("manifest 缺少 version 字段")
    return match.group(1).decode("utf-8")


def manifest_with_checksum(source: bytes, checksum: str) -> bytes:
    text = source.decode("utf-8").replace("\r\n", "\n")
    text = re.sub(r"(?m)^checksum\s*=.*\n?", "", text).rstrip("\n")
    return f"{text}\nchecksum              = {checksum}\n".encode("utf-8")


def validate_project() -> None:
    required = [
        PROJECT / "app",
        PROJECT / "cmd",
        PROJECT / "config",
        PROJECT / "manifest",
        PROJECT / "LICENSE",
        PROJECT / "ICON.PNG",
        PROJECT / "ICON_256.PNG",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.exists()]
    if missing:
        raise SystemExit("缺少打包文件：" + ", ".join(missing))


def verify_package(package: Path, *, expected_checksum: str, expected_version: str) -> None:
    with tarfile.open(package, "r:gz") as outer:
        names = set(outer.getnames())
        required = {"app.tgz", "manifest", "LICENSE", "cmd", "config", "ICON.PNG", "ICON_256.PNG"}
        if not required.issubset(names):
            raise SystemExit("FPK 外层结构校验失败")
        app_member = outer.extractfile("app.tgz")
        manifest_member = outer.extractfile("manifest")
        if app_member is None or manifest_member is None:
            raise SystemExit("FPK 缺少 app.tgz 或 manifest")
        app_data = app_member.read()
        manifest_data = manifest_member.read()
        if hashlib.md5(app_data).hexdigest() != expected_checksum:
            raise SystemExit("FPK app.tgz 校验值不一致")
        if f"checksum              = {expected_checksum}".encode() not in manifest_data:
            raise SystemExit("FPK manifest checksum 不一致")
        if read_version(manifest_data) != expected_version:
            raise SystemExit("FPK manifest version 不一致")
        with tarfile.open(fileobj=io.BytesIO(app_data), mode="r:gz") as app_archive:
            app_names = set(app_archive.getnames())
            if not {"server", "ui", "www"}.issubset(app_names):
                raise SystemExit("FPK app.tgz 结构校验失败")


def build(output_dir: Path, expected_version: str | None) -> list[Path]:
    validate_project()
    epoch = source_epoch()
    source_manifest = normalized_bytes(PROJECT / "manifest")
    version = read_version(source_manifest)
    if expected_version and version != expected_version.removeprefix("v"):
        raise SystemExit(f"标签版本 {expected_version} 与 manifest 版本 {version} 不一致")

    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="llled-fpk-") as temp_dir:
        app_tgz = Path(temp_dir) / "app.tgz"

        def write_app(archive: tarfile.TarFile) -> None:
            add_tree(archive, PROJECT / "app", epoch=epoch)

        write_gzip_tar(app_tgz, write_app, epoch=epoch)
        app_data = app_tgz.read_bytes()
        checksum = hashlib.md5(app_data).hexdigest()
        packaged_manifest = manifest_with_checksum(source_manifest, checksum)
        versioned = output_dir / f"{APP_NAME}-{version}.fpk"

        def write_outer(archive: tarfile.TarFile) -> None:
            add_bytes(archive, "app.tgz", app_data, mode=0o600, epoch=epoch)
            add_bytes(archive, "LICENSE", normalized_bytes(PROJECT / "LICENSE"), mode=0o600, epoch=epoch)
            add_directory(archive, "cmd", epoch=epoch)
            add_tree(archive, PROJECT / "cmd", prefix="cmd", command_tree=True, epoch=epoch)
            add_directory(archive, "config", epoch=epoch)
            add_tree(archive, PROJECT / "config", prefix="config", epoch=epoch)
            add_bytes(archive, "ICON.PNG", (PROJECT / "ICON.PNG").read_bytes(), mode=0o600, epoch=epoch)
            add_bytes(archive, "ICON_256.PNG", (PROJECT / "ICON_256.PNG").read_bytes(), mode=0o600, epoch=epoch)
            add_bytes(archive, "manifest", packaged_manifest, mode=0o600, epoch=epoch)

        write_gzip_tar(versioned, write_outer, epoch=epoch)
        verify_package(versioned, expected_checksum=checksum, expected_version=version)

    canonical = output_dir / f"{APP_NAME}.fpk"
    shutil.copyfile(versioned, canonical)
    sha256 = hashlib.sha256(versioned.read_bytes()).hexdigest()
    checksum_file = output_dir / f"{APP_NAME}-{version}.fpk.sha256"
    checksum_file.write_text(f"{sha256}  {versioned.name}\n", encoding="utf-8", newline="\n")

    print(f"版本: {version}")
    print(f"输出: {versioned}")
    print(f"固定名称: {canonical}")
    print(f"SHA256: {sha256}")
    return [versioned, canonical, checksum_file]


def main() -> None:
    parser = argparse.ArgumentParser(description="构建 fnOS FPK 安装包")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    parser.add_argument("--expect-version", help="要求与 manifest 一致的版本或 v 标签")
    args = parser.parse_args()
    build(args.output_dir.resolve(), args.expect_version)


if __name__ == "__main__":
    main()

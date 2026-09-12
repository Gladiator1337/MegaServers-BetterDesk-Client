#!/usr/bin/env python3
"""Pack BetterDesk desktop build trees into Generator templates.

Produces a directory (or tar.gz) the BetterDesk console can download and
patch with a signed custom.txt for Support Agent (incoming-only) builds.

Expected layout under --dist-root (per platform/arch):
  windows-x86_64/          # Release folder with betterdesk.exe (no custom.txt)
  windows-aarch64/
  linux-x86_64/            # extracted app tree or portable dir
  linux-aarch64/
  macos-x86_64/            # BetterDesk.app or Contents tree
  macos-aarch64/
  msi-template/            # optional prebuilt MSI templates from CI

Windows generator templates may additionally contain `portable-packer.exe`.
That is the generic self-extracting executable used as the immutable base for
per-customer RDPKG resource injection; it is intentionally not a custom.txt
bake-in and can therefore be reused for every customer of the same release.

Output:
  generator-templates/<platform>-<arch>/...
  generator-templates/manifest.json
  generator-templates-<version>.tar.gz (optional --archive)
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tarfile
from pathlib import Path


PLATFORMS = (
    ("windows", "x86_64", "windows-x86_64"),
    ("windows", "aarch64", "windows-aarch64"),
    ("linux", "x86_64", "linux-x86_64"),
    ("linux", "aarch64", "linux-aarch64"),
    ("macos", "x86_64", "macos-x86_64"),
    ("macos", "aarch64", "macos-aarch64"),
)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def copy_tree(src: Path, dst: Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def ensure_no_custom_txt(root: Path) -> None:
    for p in root.rglob("custom.txt"):
        p.unlink()


def pack_one(src: Path, out_dir: Path, platform: str, arch: str) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    copy_tree(src, out_dir)
    ensure_no_custom_txt(out_dir)

    # Marker for console worker: where to place custom.txt
    if platform == "macos":
        app = next(out_dir.rglob("*.app"), None)
        if app is not None:
            target = app / "Contents" / "MacOS"
            target.mkdir(parents=True, exist_ok=True)
            (target / ".custom-txt-here").write_text("place custom.txt beside betterdesk binary\n")
            inject = str(Path("Contents") / "MacOS" / "custom.txt")
        else:
            (out_dir / ".custom-txt-here").write_text("place custom.txt in this directory\n")
            inject = "custom.txt"
    else:
        (out_dir / ".custom-txt-here").write_text("place custom.txt beside betterdesk binary\n")
        inject = "custom.txt"

    archive_name = f"{platform}-{arch}.tar.gz"
    archive_path = out_dir.parent / archive_name
    with tarfile.open(archive_path, "w:gz") as tar:
        tar.add(out_dir, arcname=f"{platform}-{arch}")

    entry = {
        "platform": platform,
        "arch": arch,
        "format": "portable",
        "path": archive_name,
        "inject_custom_txt": inject,
        "sha256": sha256_file(archive_path),
        "size": archive_path.stat().st_size,
    }

    # Windows templates can carry the generic self-extracting packer used by
    # BetterDesk Console to inject a tiny per-customer RDPKG without rebuilding
    # the full Rust/Flutter client. Keep the path explicit in the manifest so a
    # future worker can feature-detect this capability without filename guessing.
    portable_packer = out_dir / "portable-packer.exe"
    if platform == "windows" and portable_packer.is_file():
        entry["portable_packer"] = {
            "path": "portable-packer.exe",
            "sha256": sha256_file(portable_packer),
            "size": portable_packer.stat().st_size,
        }

    return entry


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dist-root", type=Path, required=True, help="Root with per-platform build folders")
    parser.add_argument("--out", type=Path, required=True, help="Output directory for templates")
    parser.add_argument("--version", default=os.environ.get("VERSION", "0.0.0"))
    parser.add_argument("--archive", action="store_true", help="Also write generator-templates-<version>.tar.gz")
    args = parser.parse_args()

    out = args.out
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    entries = []
    for platform, arch, folder in PLATFORMS:
        src = args.dist_root / folder
        if not src.is_dir():
            print(f"skip missing {src}")
            continue
        dest = out / f"{platform}-{arch}"
        entries.append(pack_one(src, dest, platform, arch))
        print(f"packed {platform}-{arch}")

    msi_src = args.dist_root / "msi-template"
    if msi_src.is_dir():
        msi_out = out / "msi-template"
        copy_tree(msi_src, msi_out)
        for msi in msi_out.glob("*.msi"):
            arch = "aarch64" if "aarch64" in msi.name else "x86_64"
            entries.append(
                {
                    "platform": "windows",
                    "arch": arch,
                    "format": "msi-template",
                    "path": f"msi-template/{msi.name}",
                    "inject_custom_txt": "cab2:custom.txt",
                    "sha256": sha256_file(msi),
                    "size": msi.stat().st_size,
                }
            )

    manifest = {
        "schema_version": 1,
        "product": "betterdesk-desktop",
        "sku": "generator-templates",
        "version": args.version,
        "templates": entries,
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {out / 'manifest.json'} ({len(entries)} templates)")

    if args.archive:
        archive = out.parent / f"generator-templates-{args.version}.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(out, arcname="generator-templates")
        print(f"wrote {archive}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
#!/usr/bin/env python3
"""Fail if a shareable mod tree contains private ROM material or bad metadata."""

from __future__ import annotations

import json
import sys
from pathlib import Path


FORBIDDEN_SUFFIXES = {
    ".gba", ".gb", ".gbc", ".ips", ".ups", ".bps",
    ".exe", ".dll", ".so", ".apk", ".jar",
}
FORBIDDEN_NAMES = {"baseroms", "cache"}


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    errors: list[str] = []
    if manifest.get("profile") != "total_conversion":
        errors.append("manifest profile must be total_conversion")
    if manifest.get("games") != ["firered"]:
        errors.append("manifest must target FireRed only")
    if manifest.get("permissions") != ["engine_internals"]:
        errors.append("only the stock engine_internals permission is expected")
    imports = manifest.get("required_imports", [])
    if len(imports) != 1 or imports[0].get("id") != "radical_red_v4_1":
        errors.append("exactly one Radical Red v4.1 required import must be declared")

    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if any(part.lower() in FORBIDDEN_NAMES for part in relative.parts):
            errors.append(f"private/generated directory found: {relative}")
        if path.is_file() and path.suffix.lower() in FORBIDDEN_SUFFIXES:
            errors.append(f"private ROM/patch file found: {relative}")

    if errors:
        print("FAIL package policy")
        for error in sorted(set(errors)):
            print(f"- {error}")
        return 1
    print("PASS package policy: no ROMs, patches, baseroms, or caches included")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

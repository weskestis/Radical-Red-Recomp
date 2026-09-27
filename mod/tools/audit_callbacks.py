#!/usr/bin/env python3
"""Print compact script context around RR callnative addresses.

The original monolithic extractor output can exceed Lua 5.1's constant limit,
so this audit deliberately parses the generated Lua as text.
"""

from __future__ import annotations

import argparse
import ast
import re
from pathlib import Path


SCRIPT_RE = re.compile(r"^  (.+) = \{$")
ROW_START_RE = re.compile(r"^    \{$")
ROW_END_RE = re.compile(r"^    \},$")
FIELD_RE = re.compile(r'^      ([A-Za-z][A-Za-z0-9_]*) = (.+),$')


def load_text_snippets(path: Path | None) -> dict[str, str]:
    if path is None:
        return {}
    snippets: dict[str, list[str]] = {}
    key: str | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r'^  \["(g3:[0-9a-f]+)"\] = \{$', line)
        if match:
            key = match.group(1)
            snippets[key] = []
            continue
        match = re.match(r'^      s = (".*"),$', line)
        if key and match and len(snippets[key]) < 3:
            try:
                snippets[key].append(ast.literal_eval(match.group(1)))
            except (SyntaxError, ValueError):
                pass
    return {key: "".join(parts).replace("\n", " ") for key, parts in snippets.items()}


def row_description(
    lines: list[str], start: int, end: int, text_snippets: dict[str, str]
) -> str:
    fields: dict[str, str] = {}
    positional: list[str] = []
    for line in lines[start + 1 : end]:
        match = FIELD_RE.match(line)
        if match:
            fields[match.group(1)] = match.group(2)
            continue
        match = re.match(r"^      \[(\d+)\] = (.+),$", line)
        if match:
            positional.append(f"[{match.group(1)}]={match.group(2)}")
    op = fields.pop("op", "?").strip('"')
    useful = []
    for key in (
        "var", "value", "dest", "id", "fn", "species", "level", "item",
        "quantity", "target", "text", "std", "flag", "localId", "movement",
    ):
        if key in fields:
            value = fields[key]
            if key in {"fn", "id"}:
                try:
                    value = f"0x{int(value):X}"
                except ValueError:
                    pass
            useful.append(f"{key}={value}")
    if op == "loadword" and "value" in fields:
        pointer = fields["value"].strip('"')
        snippet = text_snippets.get(pointer)
        if snippet:
            useful.append("text=" + repr(snippet[:100]))
    return " ".join([op, *useful, *positional])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("scripts", type=Path)
    parser.add_argument("address", help="hex or decimal native address")
    parser.add_argument("--limit", type=int, default=5)
    parser.add_argument("--text", type=Path)
    args = parser.parse_args()
    address = int(args.address, 0)
    needle = f"      fn = {address},"
    lines = args.scripts.read_text(encoding="utf-8").splitlines()
    text_snippets = load_text_snippets(args.text)

    occurrences = [i for i, line in enumerate(lines) if line == needle]
    print(f"NATIVE 0x{address:08X} uses={len(occurrences)}")
    for occurrence in occurrences[: args.limit]:
        script_start = occurrence
        while script_start >= 0 and not SCRIPT_RE.match(lines[script_start]):
            script_start -= 1
        script_match = SCRIPT_RE.match(lines[script_start]) if script_start >= 0 else None
        script_name = script_match.group(1) if script_match else "?"

        starts = []
        cursor = script_start + 1
        while cursor < len(lines):
            if cursor > script_start + 1 and SCRIPT_RE.match(lines[cursor]):
                break
            if ROW_START_RE.match(lines[cursor]):
                starts.append(cursor)
            cursor += 1
        current = max((i for i, start in enumerate(starts) if start < occurrence), default=0)
        print(f"  SCRIPT {script_name} row={current + 1}")
        for row_index in range(max(0, current - 6), min(len(starts), current + 7)):
            start = starts[row_index]
            end = start + 1
            while end < len(lines) and not ROW_END_RE.match(lines[end]):
                end += 1
            marker = ">" if row_index == current else " "
            print(
                f"  {marker} {row_index + 1} "
                f"{row_description(lines, start, end, text_snippets)}"
            )


if __name__ == "__main__":
    main()

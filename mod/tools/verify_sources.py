#!/usr/bin/env python3
"""Verify the private ROM inputs and audit Radical Red's core tables."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path
from typing import Any


FIRERED_EXPECTED = {
    "size": 16_777_216,
    "md5": "e26ee0d44e809351c8ce2d73c7400cdd",
    "sha1": "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc",
    "sha256": "3d0c79f1627022e18765766f6cb5ea067f6b5bf7dca115552189ad65a5c3a8ac",
}
RADICAL_RED_EXPECTED = {
    "size": 33_554_432,
    "md5": "8529f3a45d32bce4da637976fcf269d4",
    "sha1": "964f951a0fdaf209e4ea1344883ef0d557bb3a80",
    "sha256": "679d112cdfe699c2793d82c7e7999ac9dfca9e222ad5a85d4f8f1e457cd0283f",
}

POINTER_SLOTS = {
    "battleMoves": 0x0001CC,
    "speciesNames": 0x000144,
    "baseStats": 0x0001BC,
    "eggMoves": 0x045C50,
    "tmhmLearnsets": 0x043C68,
    "tutorLearnsets": 0x120C30,
    "frontPics": 0x000128,
    "backPics": 0x00012C,
    "palettes": 0x000130,
    "shinyPalettes": 0x000134,
    "evolutions": 0x042F6C,
    "pokedexEntries": 0x088E34,
    "speciesToNationalDex": 0x04323C,
    "icons": 0x000138,
    "iconPaletteIndices": 0x00013C,
    "levelUpLearnsets": 0x03EA7C,
}

SPECIES_COUNT = 1_376
FIRERED_INTERNAL_SPECIES = 411
FIRERED_PATCHABLE_SPECIES = 386
NAME_STRIDE = 11
BASE_STATS_STRIDE = 28
BATTLE_MOVE_STRIDE = 12
FIRERED_MOVE_COUNT = 355
TYPE_COUNT = 24
TYPE_CHART_OFFSET = 0x1146CE2
VERSION_SENTINEL_OFFSET = 0x10F6D55
SAFE_OFFSETS = tuple(range(0, 6)) + (8, 9, 16, 17, 18, 19, 20, 21)

CHARMAP = {
    0x00: " ", 0x06: "É", 0x1B: "é", 0x2D: "&", 0x2E: "+",
    0x35: "=", 0x36: ";", 0x5B: "%", 0x5C: "(", 0x5D: ")",
    0x85: "<", 0x86: ">", 0xAB: "!", 0xAC: "?", 0xAD: ".",
    0xAE: "-", 0xAF: "·", 0xB4: "'", 0xB5: "♂", 0xB6: "♀",
    0xB8: ",", 0xBA: "/", 0xF0: ":",
}
CHARMAP.update({0xA1 + i: str(i) for i in range(10)})
CHARMAP.update({0xBB + i: chr(ord("A") + i) for i in range(26)})
CHARMAP.update({0xD5 + i: chr(ord("a") + i) for i in range(26)})


def digests(path: Path) -> dict[str, Any]:
    hashes = {name: hashlib.new(name) for name in ("md5", "sha1", "sha256")}
    size = 0
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            size += len(chunk)
            for digest in hashes.values():
                digest.update(chunk)
    return {"file": path.name, "size": size,
            **{name: value.hexdigest() for name, value in hashes.items()}}


def require_exact(label: str, actual: dict[str, Any], expected: dict[str, Any]) -> None:
    failures = [f"{key}: expected {value}, found {actual.get(key)}"
                for key, value in expected.items() if actual.get(key) != value]
    if failures:
        raise ValueError(f"{label} is not the required source: " + "; ".join(failures))


def pointer(rom: bytes, slot: int) -> int:
    raw = struct.unpack_from("<I", rom, slot)[0]
    if not 0x08000000 <= raw < 0x0A000000:
        raise ValueError(f"invalid GBA pointer 0x{raw:08X} at 0x{slot:X}")
    offset = raw - 0x08000000
    if not 0 <= offset < len(rom):
        raise ValueError(f"pointer at 0x{slot:X} resolves outside the ROM")
    return offset


def header(rom: bytes) -> dict[str, Any]:
    return {
        "title": rom[0xA0:0xAC].rstrip(b"\0").decode("ascii"),
        "gameCode": rom[0xAC:0xB0].decode("ascii"),
        "revision": rom[0xBC],
    }


def valid_name_record(record: bytes) -> bool:
    try:
        terminator = record.index(0xFF)
    except ValueError:
        return False
    return terminator > 0 and all(value == 0xFF for value in record[terminator:])


def decode_name(record: bytes) -> str:
    values = record.split(b"\xFF", 1)[0]
    return "".join(CHARMAP.get(value, f"{{{value:02X}}}") for value in values)


def species_record(rom: bytes, table: int, index: int) -> bytes:
    start = table + index * BASE_STATS_STRIDE
    return rom[start:start + BASE_STATS_STRIDE]


def changed_ranges(left: bytes, right: bytes) -> int:
    ranges = 0
    changing = False
    for a, b in zip(left, right):
        different = a != b
        if different and not changing:
            ranges += 1
        changing = different
    return ranges


def audit(firered_path: Path, rr_path: Path) -> dict[str, Any]:
    clean_hashes = digests(firered_path)
    rr_hashes = digests(rr_path)
    require_exact("FireRed", clean_hashes, FIRERED_EXPECTED)
    require_exact("Radical Red", rr_hashes, RADICAL_RED_EXPECTED)

    clean = firered_path.read_bytes()
    rr = rr_path.read_bytes()
    clean_header, rr_header = header(clean), header(rr)
    expected_header = {"title": "POKEMON FIRE", "gameCode": "BPRE", "revision": 0}
    if clean_header != expected_header or rr_header != expected_header:
        raise ValueError("one or both ROM headers are not FireRed US revision 0")

    embedded_version = decode_name(
        rr[VERSION_SENTINEL_OFFSET:VERSION_SENTINEL_OFFSET + 24])
    if embedded_version != "Radical Red Version v4.1":
        raise ValueError("embedded version sentinel does not identify Radical Red v4.1")

    rr_pointers = {name: pointer(rr, slot) for name, slot in POINTER_SLOTS.items()}
    clean_stats = pointer(clean, POINTER_SLOTS["baseStats"])
    rr_names = rr_pointers["speciesNames"]
    rr_stats = rr_pointers["baseStats"]
    rr_moves = rr_pointers["battleMoves"]

    detected = None
    decoded_names: list[str] = []
    for index in range(SPECIES_COUNT + 1):
        start = rr_names + index * NAME_STRIDE
        record = rr[start:start + NAME_STRIDE]
        if not valid_name_record(record):
            detected = index
            break
        decoded_names.append(decode_name(record))
    if detected != SPECIES_COUNT:
        raise ValueError(f"expected {SPECIES_COUNT} species records, found {detected}")
    if decoded_names[1] != "Bulbasaur" or decoded_names[-1] != "Chillet":
        raise ValueError("Radical Red species-table sentinels do not match v4.1")

    changed_safe: list[int] = []
    fairy_ids: list[int] = []
    populated_ids: list[int] = []
    reserved_ids: list[int] = []
    for index in range(1, FIRERED_INTERNAL_SPECIES + 1):
        before = species_record(clean, clean_stats, index)
        after = species_record(rr, rr_stats, index)
        if not all(after[offset] > 0 for offset in range(6)):
            reserved_ids.append(index)
            continue
        populated_ids.append(index)
        if any(before[offset] != after[offset] for offset in SAFE_OFFSETS):
            changed_safe.append(index)
        if 23 in after[6:8]:
            fairy_ids.append(index)

    expected_fairy = [35, 36, 39, 40, 122, 154, 173, 174, 175, 176, 182,
                      183, 184, 209, 210, 325, 350, 355, 375, 387, 392, 393, 394]
    if len(populated_ids) != FIRERED_PATCHABLE_SPECIES:
        raise ValueError(
            f"populated FireRed record sentinel changed: expected "
            f"{FIRERED_PATCHABLE_SPECIES}, found {len(populated_ids)}")
    if reserved_ids != list(range(252, 277)):
        raise ValueError("reserved species sentinel set changed")
    if len(changed_safe) != 344:
        raise ValueError(f"safe-field delta sentinel changed: expected 344, found {len(changed_safe)}")
    if fairy_ids != expected_fairy:
        raise ValueError("Fairy-type sentinel set changed")

    if rr_moves != 0x11521D0:
        raise ValueError(
            f"battle-move pointer sentinel changed: expected 0x11521D0, found 0x{rr_moves:X}")
    split_names = {0: "physical", 1: "special", 2: "status"}
    split_counts = {name: 0 for name in split_names.values()}
    move_rows: list[dict[str, Any]] = []
    for index in range(FIRERED_MOVE_COUNT):
        start = rr_moves + index * BATTLE_MOVE_STRIDE
        row = rr[start:start + BATTLE_MOVE_STRIDE]
        if len(row) != BATTLE_MOVE_STRIDE:
            raise ValueError(f"truncated battle-move record {index}")
        split = row[10]
        if split not in split_names:
            raise ValueError(f"unsupported move split {split} at move {index}")
        category = split_names[split]
        split_counts[category] += 1
        move_rows.append({
            "id": index, "effect": row[0], "power": row[1], "type": row[2],
            "accuracy": row[3], "pp": row[4], "category": category,
        })
    expected_splits = {"physical": 139, "special": 80, "status": 136}
    if split_counts != expected_splits:
        raise ValueError(
            f"move-category count sentinel changed: expected {expected_splits}, found {split_counts}")
    move_sentinels = {1: "physical", 14: "status", 44: "physical",
                      52: "special", 247: "special"}
    if any(move_rows[index]["category"] != category
           for index, category in move_sentinels.items()):
        raise ValueError("move-category sentinels do not match Radical Red v4.1")

    chart = rr[TYPE_CHART_OFFSET:TYPE_CHART_OFFSET + TYPE_COUNT * TYPE_COUNT]
    if len(chart) != TYPE_COUNT * TYPE_COUNT:
        raise ValueError("truncated Radical Red type chart")

    def type_multiplier(attacking: int, defending: int) -> int:
        raw = chart[attacking * TYPE_COUNT + defending]
        if raw == 0:
            return 10
        if raw == 1:
            return 0
        if raw not in (5, 10, 20):
            raise ValueError(
                f"unsupported type multiplier {raw} at {attacking}>{defending}")
        return raw

    chart_sentinels = {
        "NORMAL>GHOST": type_multiplier(0, 7),
        "DRAGON>FAIRY": type_multiplier(16, 23),
        "FAIRY>DRAGON": type_multiplier(23, 16),
        "DARK>STEEL": type_multiplier(17, 8),
        "GHOST>STEEL": type_multiplier(7, 8),
        "POISON>FAIRY": type_multiplier(3, 23),
    }
    expected_chart = {
        "NORMAL>GHOST": 0, "DRAGON>FAIRY": 0, "FAIRY>DRAGON": 20,
        "DARK>STEEL": 10, "GHOST>STEEL": 10, "POISON>FAIRY": 20,
    }
    if chart_sentinels != expected_chart:
        raise ValueError("modern type-chart sentinels do not match Radical Red v4.1")

    first_window_rr = rr[:len(clean)]
    different_bytes = sum(a != b for a, b in zip(clean, first_window_rr))
    pointers = {
        name: {"slot": f"0x{POINTER_SLOTS[name]:X}", "offset": f"0x{offset:X}"}
        for name, offset in sorted(rr_pointers.items())
    }
    bulbasaur = species_record(rr, rr_stats, 1)

    return {
        "profile": "RADICAL_RED_V4_1",
        "result": "PASS",
        "sources": {
            "firered": {**clean_hashes, "header": clean_header},
            "radicalRed": {**rr_hashes, "header": rr_header},
        },
        "radicalRedTables": {
            "speciesCount": detected,
            "embeddedVersion": embedded_version,
            "firstSpecies": decoded_names[1],
            "lastSpecies": decoded_names[-1],
            "nameStride": NAME_STRIDE,
            "baseStatsStride": BASE_STATS_STRIDE,
            "pointers": pointers,
            "bulbasaur": {
                "stats": list(bulbasaur[0:6]),
                "typeIds": list(bulbasaur[6:8]),
            },
        },
        "speciesOverlay": {
            "fireRedInternalSlots": FIRERED_INTERNAL_SPECIES,
            "populatedRecordsPatched": len(populated_ids),
            "reservedRecordsSkipped": len(reserved_ids),
            "reservedInternalIds": reserved_ids,
            "recordsWithSafeFieldChanges": len(changed_safe),
            "fairyRecordsPromoted": len(fairy_ids),
            "fairyInternalIds": fairy_ids,
            "safeStructOffsets": list(SAFE_OFFSETS),
            "promotedTypeOffsets": [6, 7],
        },
        "battlePrimitives": {
            "battleMovePointer": f"0x{rr_moves:X}",
            "battleMoveStride": BATTLE_MOVE_STRIDE,
            "fireRedMoveRecords": FIRERED_MOVE_COUNT,
            "categoryCounts": split_counts,
            "moveCategorySentinels": {
                str(index): move_rows[index]["category"]
                for index in move_sentinels
            },
            "typeCount": TYPE_COUNT,
            "fairyTypeId": 23,
            "typeChartOffset": f"0x{TYPE_CHART_OFFSET:X}",
            "typeChartSentinels": chart_sentinels,
        },
        "binaryComparison": {
            "comparedBytes": len(clean),
            "differentBytes": different_bytes,
            "differentPercent": round(100 * different_bytes / len(clean), 6),
            "changedRanges": changed_ranges(clean, first_window_rr),
            "expandedBytes": len(rr) - len(clean),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--firered", type=Path, required=True)
    parser.add_argument("--radical-red", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    report = audit(args.firered, args.radical_red)
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

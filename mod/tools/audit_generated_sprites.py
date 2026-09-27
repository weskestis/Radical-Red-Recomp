#!/usr/bin/env python3
"""Audit every RR-generated RGBA asset and the ROM tables behind core art.

Usage:
  python3 tools/audit_generated_sprites.py RADICAL_RED.gba GENERATED_GBA_ROOT

This intentionally reads raw .rgba files.  It checks the complete generated
asset set for truncation/blank-black failures, then independently verifies the
overworld, Pokemon, trainer, and item families against Radical Red v4.1's ROM
pointers and palettes.
"""

from __future__ import annotations

import hashlib
import struct
import sys
from pathlib import Path


EXPECTED_MD5 = "8529f3a45d32bce4da637976fcf269d4"
EXPECTED_RGBA_COUNT = 9530
SPECIES_COUNT = 1376
OW_COUNT = 545
OW_PALETTE_COUNT = 451
TRAINER_FRONT_COUNT = 148
ITEM_COUNT = 750

OW_POINTERS = 0x0EB1000
OW_POKEMON_POINTERS = 0x134FD7C
OW_PLAYER_POINTERS = 0x134FCB8
OW_PALETTES = 0x035CCC8
MON_FRONT = 0x17FA1C4
MON_BACK = 0x17B6DC4
MON_NORMAL_PAL = 0x1811208
MON_SHINY_PAL = 0x181EDC8
MON_ICONS = 0x17FE6CC
MON_ICON_PAL_INDEX = 0x17FE164
MON_ICON_PALS = 0x03D3740
TRAINER_FRONT = 0x23957C
TRAINER_FRONT_PAL = 0x239A1C
TRAINER_BACK = 0x239FA4
TRAINER_BACK_PAL = 0x239FD4
ITEM_ICONS = 0x13C8100
NAMING_RIVAL_GFX = 0x0EE82B0
NAMING_RIVAL_FRAME_TABLE = 0x0EB4E58
NAMING_RIVAL_PALETTE = 0x0E98004


class AuditError(RuntimeError):
    pass


def need(condition: bool, message: str) -> None:
    if not condition:
        raise AuditError(message)


def u16(data: bytes, offset: int) -> int:
    need(0 <= offset <= len(data) - 2, f"u16 outside ROM at 0x{offset:X}")
    return struct.unpack_from("<H", data, offset)[0]


def s16(data: bytes, offset: int) -> int:
    value = u16(data, offset)
    return value - 0x10000 if value >= 0x8000 else value


def u32(data: bytes, offset: int) -> int:
    need(0 <= offset <= len(data) - 4, f"u32 outside ROM at 0x{offset:X}")
    return struct.unpack_from("<I", data, offset)[0]


def gba_offset(data: bytes, pointer: int, label: str) -> int:
    need(0x08000000 <= pointer < 0x0A000000,
         f"{label}: invalid GBA pointer 0x{pointer:08X}")
    offset = pointer - 0x08000000
    need(offset < len(data), f"{label}: pointer is beyond the ROM")
    return offset


def lz77(data: bytes, offset: int, label: str) -> bytes:
    need(offset + 4 <= len(data) and data[offset] == 0x10,
         f"{label}: missing GBA LZ77 header at 0x{offset:X}")
    size = int.from_bytes(data[offset + 1:offset + 4], "little")
    need(0 < size <= 0x1000000, f"{label}: invalid LZ77 size {size}")
    source = offset + 4
    out = bytearray()
    while len(out) < size:
        need(source < len(data), f"{label}: truncated LZ77 flag stream")
        flags = data[source]
        source += 1
        for bit in range(7, -1, -1):
            if len(out) >= size:
                break
            if flags & (1 << bit):
                need(source + 2 <= len(data),
                     f"{label}: truncated LZ77 back-reference")
                first, second = data[source], data[source + 1]
                source += 2
                length = (first >> 4) + 3
                distance = ((first & 0x0F) << 8) | second
                start = len(out) - distance - 1
                need(start >= 0, f"{label}: invalid LZ77 distance")
                for _ in range(length):
                    out.append(out[start])
                    start += 1
                    if len(out) >= size:
                        break
            else:
                need(source < len(data), f"{label}: truncated LZ77 literal")
                out.append(data[source])
                source += 1
    return bytes(out)


def rgb555(value: int) -> tuple[int, int, int]:
    r5 = value & 31
    g5 = (value >> 5) & 31
    b5 = (value >> 10) & 31
    return (
        (r5 * 255 + 15) // 31,
        (g5 * 255 + 15) // 31,
        (b5 * 255 + 15) // 31,
    )


def palette_colors(raw: bytes, bank: int = 0) -> set[tuple[int, int, int]]:
    base = bank * 32
    need(len(raw) >= base + 32, f"palette bank {bank} is truncated")
    return {rgb555(struct.unpack_from("<H", raw, base + i * 2)[0])
            for i in range(1, 16)}


def rgba_stats(path: Path, expected_size: int | None = None):
    need(path.is_file(), f"missing {path}")
    raw = path.read_bytes()
    need(raw and len(raw) % 4 == 0, f"malformed RGBA file {path}")
    if expected_size is not None:
        need(len(raw) == expected_size,
             f"{path}: expected {expected_size} bytes, got {len(raw)}")
    alpha = raw[3::4]
    need(set(alpha) <= {0, 255}, f"{path}: non-binary alpha values")
    opaque = {
        (raw[i], raw[i + 1], raw[i + 2])
        for i in range(0, len(raw), 4) if raw[i + 3]
    }
    opaque_pixels = sum(1 for value in alpha if value)
    all_black = bool(opaque_pixels) and opaque == {(0, 0, 0)}
    return raw, opaque, opaque_pixels, all_black


def validate_palette(path: Path, colors: set[tuple[int, int, int]],
                     *, allow_blank: bool = False) -> None:
    _, actual, opaque_pixels, _ = rgba_stats(path)
    if not allow_blank:
        need(opaque_pixels > 0, f"{path}: unexpectedly blank")
    unexpected = actual - colors
    need(not unexpected,
         f"{path}: {len(unexpected)} color(s) are outside its ROM palette")


def audit_all_rgba(root: Path) -> list[Path]:
    files = sorted(root.rglob("*.rgba"))
    need(len(files) == EXPECTED_RGBA_COUNT,
         f"expected {EXPECTED_RGBA_COUNT} RGBA assets, found {len(files)}")
    allowed_blank = {
        "trainers/front/0.rgba",
        "pokemon/back/412.rgba",
        "pokemon/back_shiny/412.rgba",
        "pokemon/party/slot_wide_empty.rgba",
        "pokemon/party/status_balls.rgba",
    }
    allowed_black = {
        "items/bag/list_blank.rgba",
        "items/bag/list_blank_female.rgba",
        "pokemon/summary/pokerus.rgba",
    }
    for path in files:
        rel = path.relative_to(root).as_posix()
        _, _, opaque_pixels, all_black = rgba_stats(path)
        if not opaque_pixels:
            need(rel in allowed_blank
                 or rel.startswith("pokemon/pokedex/footprints/"),
                 f"{rel}: unexpected fully transparent asset")
        if all_black:
            need(rel in allowed_black
                 or rel.startswith("pokemon/pokedex/footprints/"),
                 f"{rel}: unexpected all-black asset")
    return files


def audit_overworld(rom: bytes, root: Path) -> None:
    palette_by_tag: dict[int, set[tuple[int, int, int]]] = {}
    for index in range(OW_PALETTE_COUNT):
        entry = OW_PALETTES + index * 8
        pal_offset = gba_offset(rom, u32(rom, entry),
                                f"overworld palette {index}")
        tag = u16(rom, entry + 4)
        need(tag != 0 and tag not in palette_by_tag,
             f"overworld palette {index}: zero/duplicate tag 0x{tag:04X}")
        palette_by_tag[tag] = {
            rgb555(u16(rom, pal_offset + color * 2))
            for color in range(1, 16)
        }

    tables = (
        (0, OW_POINTERS, 256),
        (1, OW_POKEMON_POINTERS, 240),
        (2, OW_PLAYER_POINTERS, 49),
    )
    infos: list[tuple[int, int]] = []
    image_starts: set[int] = set()
    for selector, pointers, count in tables:
        for index in range(count):
            graphics_id = selector * 0x100 + index
            info = gba_offset(rom, u32(rom, pointers + index * 4),
                              f"overworld graphic 0x{graphics_id:04X}")
            infos.append((graphics_id, info))
            image_starts.add(gba_offset(
                rom, u32(rom, info + 0x1C),
                f"overworld graphic 0x{graphics_id:04X} images"))
    need(len(infos) == OW_COUNT,
         f"expected {OW_COUNT} addressable overworld mappings, got {len(infos)}")

    # The physical ordinary table has a 257th Red alias, but 0x0100 is the
    # encoded selector-1/index-0 value in RR's live resolver and therefore the
    # alias cannot have its own cache filename.
    alias = gba_offset(rom, u32(rom, OW_POINTERS + 256 * 4),
                       "ordinary overworld alias 256")
    need(alias == gba_offset(rom, u32(rom, OW_POINTERS), "Red overworld"),
         "ordinary overworld alias 256 no longer points at Red")
    # The extractor also recognizes adjacent graphics-info structs that share
    # a top-level pointer; include their image-table starts when counting frames.
    known = {info for _, info in infos}
    for _, first in tuple(infos):
        info = first + 0x24
        while info + 0x24 <= len(rom) and info not in known:
            if u16(rom, info) != 0xFFFF:
                break
            anim = u32(rom, info + 0x18)
            images = u32(rom, info + 0x1C)
            if not (0x08000000 <= anim < 0x0A000000
                    and 0x08000000 <= images < 0x0A000000):
                break
            known.add(info)
            image_starts.add(gba_offset(rom, images, "adjacent OW images"))
            info += 0x24

    used_tags: set[int] = set()
    for graphics_id, info in infos:
        meta_path = root / "ow" / f"{graphics_id}.meta"
        meta = meta_path.read_bytes() if meta_path.is_file() else b""
        need(len(meta) == 16 and meta[:4] == b"SVOW",
             f"overworld {graphics_id}: malformed metadata")
        _, fmt, inanimate_byte, meta_id, meta_w, meta_h, meta_frames, meta_tag = \
            struct.unpack("<4sBBHHHHH", meta)
        need(fmt == 1 and meta_id == graphics_id,
             f"overworld {graphics_id}: metadata identity mismatch")

        tag = u16(rom, info + 2)
        width, height = abs(s16(rom, info + 8)), abs(s16(rom, info + 10))
        flags = rom[info + 12]
        inanimate = bool((flags >> 6) & 1)
        output_width = 16 if inanimate and width == 32 and height == 16 else width
        need((meta_tag, meta_w, meta_h, bool(inanimate_byte))
             == (tag, output_width, height, inanimate),
             f"overworld {graphics_id}: ROM metadata mismatch")
        need(tag in palette_by_tag,
             f"overworld {graphics_id}: missing palette tag 0x{tag:04X}")
        used_tags.add(tag)

        images = gba_offset(rom, u32(rom, info + 0x1C),
                            f"overworld graphic {graphics_id} images")
        frame_bytes = width * height // 2
        frames = 0
        while frames < 32:
            entry = images + frames * 8
            if frames and entry in image_starts:
                break
            if entry + 8 > len(rom):
                break
            pointer = u32(rom, entry)
            if not (0x08000000 <= pointer < 0x0A000000):
                break
            if u16(rom, entry + 4) != frame_bytes:
                break
            gba_offset(rom, pointer, f"overworld {graphics_id} frame {frames}")
            frames += 1
        if frames < 1:
            frames = 1
        need(meta_frames == frames,
             f"overworld {graphics_id}: expected {frames} frames, got {meta_frames}")
        path = root / "ow" / f"{graphics_id}.rgba"
        raw, colors, opaque_pixels, _ = rgba_stats(
            path, output_width * height * frames * 4)
        need(not (colors - palette_by_tag[tag]),
             f"overworld {graphics_id}: output color outside palette 0x{tag:04X}")
        frame_size = output_width * height * 4
        for frame in range(frames):
            block = raw[frame * frame_size:(frame + 1) * frame_size]
            need(any(block[i] for i in range(3, len(block), 4)),
                 f"overworld {graphics_id}: blank frame {frame}")
        need(opaque_pixels > 0, f"overworld {graphics_id}: blank sheet")
    need(len(used_tags) == 397,
         f"expected 397 used overworld palettes, found {len(used_tags)}")


def compressed_palette(rom: bytes, table: int, index: int, label: str) -> bytes:
    pointer = u32(rom, table + index * 8)
    return lz77(rom, gba_offset(rom, pointer, label), label)


def audit_pokemon(rom: bytes, root: Path) -> None:
    families = {
        "front": MON_FRONT,
        "back": MON_BACK,
        "front_shiny": MON_FRONT,
        "back_shiny": MON_BACK,
    }
    numeric_expected = {f"{index}.rgba" for index in range(SPECIES_COUNT)}
    for family in families:
        found = {path.name for path in (root / "pokemon" / family).glob("*.rgba")
                 if path.stem.isdigit()}
        need(found == numeric_expected,
             f"pokemon/{family}: numeric species file set is incomplete")

    for species in range(SPECIES_COUNT):
        normal_raw = compressed_palette(
            rom, MON_NORMAL_PAL, species, f"species {species} normal palette")
        shiny_raw = compressed_palette(
            rom, MON_SHINY_PAL, species, f"species {species} shiny palette")
        normal = palette_colors(normal_raw)
        shiny = palette_colors(shiny_raw)
        for family, pic_table in families.items():
            pic_offset = gba_offset(
                rom, u32(rom, pic_table + species * 8),
                f"species {species} {family} picture")
            need(rom[pic_offset] == 0x10,
                 f"species {species} {family}: picture is not LZ77 data")
            path = root / "pokemon" / family / f"{species}.rgba"
            allow_blank = species == 412 and family in {"back", "back_shiny"}
            rgba_stats(path, 64 * 64 * 4)
            validate_palette(path, shiny if family.endswith("shiny") else normal,
                             allow_blank=allow_blank)

        icon_path = root / "pokemon" / "icons" / f"{species}.rgba"
        icon_offset = gba_offset(
            rom, u32(rom, MON_ICONS + species * 4),
            f"species {species} icon")
        need(icon_offset + 1024 <= len(rom),
             f"species {species}: icon data is truncated")
        pal_index = rom[MON_ICON_PAL_INDEX + species]
        if pal_index >= 6:
            pal_index = 0
        icon_pal = rom[MON_ICON_PALS + pal_index * 32:
                       MON_ICON_PALS + (pal_index + 1) * 32]
        rgba_stats(icon_path, 32 * 64 * 4)
        validate_palette(icon_path, palette_colors(icon_pal))

    # Castform's three extra sheets use both frame and palette bank 1..3.
    for family in families:
        raw_pal = compressed_palette(
            rom,
            MON_SHINY_PAL if family.endswith("shiny") else MON_NORMAL_PAL,
            385, f"Castform {family} palette")
        for form in range(1, 4):
            path = root / "pokemon" / family / f"385_{form}.rgba"
            rgba_stats(path, 64 * 64 * 4)
            validate_palette(path, palette_colors(raw_pal, form))
    rgba_stats(root / "pokemon" / "front" / "ghost.rgba", 64 * 64 * 4)


def audit_trainers(rom: bytes, root: Path) -> None:
    front_dir = root / "trainers" / "front"
    found = {path.name for path in front_dir.glob("*.rgba")}
    need(found == {f"{index}.rgba" for index in range(TRAINER_FRONT_COUNT)},
         "trainer front sprite set is incomplete")
    for trainer in range(TRAINER_FRONT_COUNT):
        pic_offset = gba_offset(
            rom, u32(rom, TRAINER_FRONT + trainer * 8),
            f"trainer front {trainer}")
        need(rom[pic_offset] == 0x10,
             f"trainer front {trainer}: picture is not LZ77 data")
        pal = compressed_palette(
            rom, TRAINER_FRONT_PAL, trainer, f"trainer front {trainer} palette")
        path = front_dir / f"{trainer}.rgba"
        rgba_stats(path, 64 * 64 * 4)
        validate_palette(path, palette_colors(pal), allow_blank=trainer == 0)

    for trainer in range(6):
        entry = TRAINER_BACK + trainer * 8
        pic_offset = gba_offset(rom, u32(rom, entry), f"trainer back {trainer}")
        size = u16(rom, entry + 4)
        if size < 0x800:
            size = 0x2800
        need(pic_offset + size <= len(rom),
             f"trainer back {trainer}: raw picture is truncated")
        frames = max(1, size // 0x800)
        pal = compressed_palette(
            rom, TRAINER_BACK_PAL, trainer, f"trainer back {trainer} palette")
        path = root / "trainers" / f"back_{trainer}.rgba"
        rgba_stats(path, 64 * 64 * frames * 4)
        validate_palette(path, palette_colors(pal))


def audit_items(rom: bytes, root: Path) -> None:
    icon_dir = root / "items" / "bag" / "icons"
    found = {path.name for path in icon_dir.glob("*.rgba")}
    need(found == {f"{index}.rgba" for index in range(ITEM_COUNT)},
         "item icon set is incomplete")
    for item in range(ITEM_COUNT):
        entry = ITEM_ICONS + item * 8
        picture = gba_offset(rom, u32(rom, entry), f"item {item} icon")
        palette = gba_offset(rom, u32(rom, entry + 4), f"item {item} palette")
        pic_raw = lz77(rom, picture, f"item {item} icon")
        pal_raw = lz77(rom, palette, f"item {item} palette")
        need(len(pic_raw) >= 24 * 24 // 2,
             f"item {item}: decompressed icon is truncated")
        path = icon_dir / f"{item}.rgba"
        rgba_stats(path, 24 * 24 * 4)
        validate_palette(path, palette_colors(pal_raw))


def audit_naming_rival(rom: bytes) -> None:
    """Verify RR's relocated nine-frame Blue sheet, not FireRed's erased slot."""
    frame_size = 0x100  # 16x32, 4bpp
    frame_count = 9
    sheet = rom[NAMING_RIVAL_GFX:
                NAMING_RIVAL_GFX + frame_size * frame_count]
    need(len(sheet) == frame_size * frame_count,
         "naming rival sheet is truncated")

    palette = {
        u16(rom, NAMING_RIVAL_PALETTE + index * 2)
        for index in range(1, 16)
    }
    need(len(palette) >= 4, "naming rival palette is unexpectedly flat")

    for frame in range(frame_count):
        raw = sheet[frame * frame_size:(frame + 1) * frame_size]
        indices = {nibble for byte in raw for nibble in (byte & 15, byte >> 4)}
        opaque = indices - {0}
        need(opaque, f"naming rival frame {frame} is blank")
        need(len(opaque) >= 3,
             f"naming rival frame {frame} is a solid/corrupt block")
        need(max(opaque) <= 15,
             f"naming rival frame {frame} has an invalid palette index")

        entry = NAMING_RIVAL_FRAME_TABLE + frame * 8
        expected_pointer = 0x08000000 + NAMING_RIVAL_GFX + frame * frame_size
        need(u32(rom, entry) == expected_pointer,
             f"naming rival frame-table pointer {frame} is wrong")
        need(u16(rom, entry + 4) == frame_size,
             f"naming rival frame-table size {frame} is wrong")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    rom_path, root = Path(argv[1]), Path(argv[2])
    rom = rom_path.read_bytes()
    need(len(rom) == 33554432, f"wrong ROM size: {len(rom)}")
    need(hashlib.md5(rom).hexdigest() == EXPECTED_MD5,
         "sprite audit requires the exact Radical Red v4.1 ROM")
    need(root.is_dir(), f"generated root does not exist: {root}")

    rgba_files = audit_all_rgba(root)
    audit_overworld(rom, root)
    audit_pokemon(rom, root)
    audit_trainers(rom, root)
    audit_items(rom, root)
    audit_naming_rival(rom)
    print(f"PASS sprite_audit: {len(rgba_files)} RGBA assets")
    print("  overworld: 545 sheets, 546 physical ROM mappings, 397 palettes")
    print("  Pokemon: 1,376 front/back/shiny sets and 1,376 icons")
    print("  trainers: 148 front sheets and 6 player-back sheets")
    print("  items: 750 ROM-backed bag icons")
    print("  naming: 9 relocated rival frames and live frame-table mappings")
    print("  no unexpected blank or all-black generated asset")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except (AuditError, OSError) as exc:
        print(f"FAIL sprite_audit: {exc}", file=sys.stderr)
        raise SystemExit(1)

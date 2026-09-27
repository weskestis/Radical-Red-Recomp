#!/usr/bin/env python3
"""Disassemble a Thumb region from a GBA ROM through the installed LLVM."""

from __future__ import annotations

import argparse
import ctypes
import struct
from pathlib import Path


LLVM_PATH = "/usr/lib/x86_64-linux-gnu/libLLVM.so.20.1"
ROM_BASE = 0x08000000


def make_disassembler() -> tuple[ctypes.CDLL, int]:
    llvm = ctypes.CDLL(LLVM_PATH)
    for name in (
        "LLVMInitializeARMTargetInfo",
        "LLVMInitializeARMTarget",
        "LLVMInitializeARMTargetMC",
        "LLVMInitializeARMDisassembler",
    ):
        getattr(llvm, name)()
    llvm.LLVMCreateDisasm.argtypes = [
        ctypes.c_char_p,
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_void_p,
        ctypes.c_void_p,
    ]
    llvm.LLVMCreateDisasm.restype = ctypes.c_void_p
    llvm.LLVMDisasmInstruction.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_uint64,
        ctypes.c_uint64,
        ctypes.c_char_p,
        ctypes.c_size_t,
    ]
    llvm.LLVMDisasmInstruction.restype = ctypes.c_size_t
    context = llvm.LLVMCreateDisasm(b"thumbv4t-none-eabi", None, 0, None, None)
    if not context:
        raise RuntimeError("LLVM ARM/Thumb disassembler unavailable")
    return llvm, context


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("rom", type=Path)
    parser.add_argument("address", type=lambda value: int(value, 0))
    parser.add_argument("size", type=lambda value: int(value, 0))
    args = parser.parse_args()
    rom = args.rom.read_bytes()
    start = args.address & ~1
    offset = start - ROM_BASE
    data = rom[offset : offset + args.size]
    llvm, context = make_disassembler()
    buffer = (ctypes.c_uint8 * len(data)).from_buffer_copy(data)

    cursor = 0
    while cursor < len(data):
        output = ctypes.create_string_buffer(256)
        used = llvm.LLVMDisasmInstruction(
            context,
            ctypes.cast(ctypes.byref(buffer, cursor), ctypes.POINTER(ctypes.c_uint8)),
            len(data) - cursor,
            start + cursor,
            output,
            len(output),
        )
        text = output.value.decode("utf-8", errors="replace") if used else "?"
        used = used or 2
        annotation = ""
        if used == 2 and cursor + 2 <= len(data):
            halfword = struct.unpack_from("<H", data, cursor)[0]
            if halfword & 0xF800 == 0x4800:
                literal = (((start + cursor + 4) & ~3) + (halfword & 0xFF) * 4)
                literal_offset = literal - ROM_BASE
                if 0 <= literal_offset <= len(rom) - 4:
                    value = struct.unpack_from("<I", rom, literal_offset)[0]
                    annotation = f" ; [0x{literal:08X}]=0x{value:08X}"
        raw = data[cursor : cursor + used].hex()
        print(f"{start + cursor:08X}: {raw:<10} {text}{annotation}")
        cursor += used


if __name__ == "__main__":
    main()

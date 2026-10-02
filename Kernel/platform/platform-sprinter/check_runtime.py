#!/usr/bin/env python3
"""Compare a MAME user image with the original relocatable FUZIX Z80 binary."""
import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--map", type=Path,
                        help="linker map: compare code only, excluding mutable initialized data")
    args = parser.parse_args()
    live = args.snapshot.read_bytes()
    source = args.binary.read_bytes()
    if len(live) != 65536:
        parser.error("snapshot must contain four 16 KB windows from a valid exec")
    base = source[2] << 8
    entry = int.from_bytes(source[12:14], "little")
    if source[entry:entry + 4] != bytes.fromhex("D5 D9 D1 21"):
        parser.error("binary does not use crt0_z80_rel")
    if base + len(source) > 65536:
        parser.error("binary exceeds the Z80 address space")
    expected = bytearray(65536)
    expected[base:base + len(source)] = source
    stream = base + int.from_bytes(source[entry + 4:entry + 6], "little")
    text_end = stream
    pos = base
    sites = 0
    while stream < base + len(source):
        step = expected[stream]
        stream += 1
        if step == 0:
            break
        if step == 255:
            pos += 254
            continue
        pos += step
        if pos >= text_end:
            parser.error("relocation site lies outside text")
        expected[pos] = (expected[pos] + (base >> 8)) & 255
        sites += 1
    else:
        parser.error("unterminated relocation stream")
    # Sprinter's existing bring-up loader retargets the libc call-0 wrapper.
    for pos in range(base + entry, text_end - 3):
        if expected[pos:pos + 4] == bytes.fromhex("CD 00 00 D0"):
            expected[pos + 1:pos + 3] = base.to_bytes(2, "little")
    limit = text_end
    label = "loaded image"
    if args.map:
        data = [int(fields[0], 16) + base
                for line in args.map.read_text().splitlines()
                if len(fields := line.split()) == 3 and fields[2] == "__data"]
        if len(data) != 1 or not base + entry < data[0] <= text_end:
            parser.error("map must define __data within the loaded image")
        limit = data[0]
        label = "code"
    bad = [pos for pos in range(base + entry, limit)
           if expected[pos] != live[pos]]
    print(f"{sites} relocation sites; {label} {base + entry:04X}..{limit - 1:04X}; "
          f"{len(bad)} differing bytes")
    if bad:
        print("First differences (address: expected -> actual):")
        print(" ".join(f"{pos:04X}: {expected[pos]:02X}->{live[pos]:02X}"
                       for pos in bad[:16]))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

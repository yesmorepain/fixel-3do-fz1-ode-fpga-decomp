#!/usr/bin/env python3
"""Extract the iCE40 bitstream from Fixel's official FZ-1 ODE firmware image.

Usage: python3 tools/extract_bitstream.py <update.ode>

Checks that the input is the official update.ode rev 1.0, then writes original/update.ode and
original/fpga_bitstream.bin (both git-ignored; Fixel's files are not redistributed).
"""
import hashlib, os, sys

OFFICIAL_SHA256 = "5e98519d83c22605031a182acb6ecb3f4391aef2b922b02ec4ccb38918cf2fec"
OFFICIAL_SIZE = 145676
BITSTREAM_OFFSET = 0x1001f945 - 0x10010000     # image is linked at 0x10010000
BITSTREAM_SIZE = 71338
BITSTREAM_SHA256 = "4d7086168e5d38863e5e079649b3568831b3a87a24d24f28d1854452830d0af8"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def write(rel, data):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    print("wrote", rel)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    if len(data) != OFFICIAL_SIZE or hashlib.sha256(data).hexdigest() != OFFICIAL_SHA256:
        sys.exit("not the official update.ode rev 1.0")
    bitstream = data[BITSTREAM_OFFSET:BITSTREAM_OFFSET + BITSTREAM_SIZE]
    if hashlib.sha256(bitstream).hexdigest() != BITSTREAM_SHA256:
        sys.exit("bitstream hash mismatch")
    if os.path.abspath(sys.argv[1]) != os.path.join(ROOT, "original", "update.ode"):
        write("original/update.ode", data)
    write("original/fpga_bitstream.bin", bitstream)


if __name__ == "__main__":
    main()

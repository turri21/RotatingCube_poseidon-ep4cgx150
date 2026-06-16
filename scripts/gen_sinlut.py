#!/usr/bin/env python3
"""
gen_sinlut.py
Generates sinlut.hex for use with $readmemh in cube3d.sv
256 entries, Q1.14 signed (16-bit), range -16384..+16384
"""
import math

ENTRIES = 256
SCALE   = 16384   # 2^14

with open("sinlut.hex", "w") as f:
    for i in range(ENTRIES):
        angle = 2 * math.pi * i / ENTRIES
        val   = round(math.sin(angle) * SCALE)
        # Clamp and convert to unsigned 16-bit two's complement
        val = max(-SCALE, min(SCALE - 1, val))
        if val < 0:
            val += 65536
        f.write(f"{val:04X}\n")

print("Generated sinlut.hex  (256 entries, Q1.14 signed)")

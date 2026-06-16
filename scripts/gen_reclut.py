#!/usr/bin/env python3
"""
gen_reclut.py
reclut.hex — reciprocal LUT for cube3d.sv perspective projection
512 entries: recip[i] = round(65536 / (i + 64))
covers z_cam range [64, 575]
"""


with open("reclut.hex", "w") as f:
    for i in range(512):
        z = i + 64
        v = min(65535, round(65536.0 / z))
        f.write(f"{v:04X}\n")

print("reclut.hex generated (512 entries)")

#!/usr/bin/env python3
"""Emit 16 OpenSCAD --camera strings: turntable rotation around Z, fixed elevation."""
import math, sys

# camera spec: translate_x,y,z,rotate_x,y,z,distance
# We orbit around origin at 25 degrees elevation, 200 units back.
ELEVATION_DEG = 25
DISTANCE = 200
N = 16

for i in range(N):
    az = (360.0 / N) * i
    # OpenSCAD rotate is XYZ Euler. Rotate first by elevation around X, then azimuth around Z.
    rotx = ELEVATION_DEG
    roty = 0
    rotz = az
    print(f"0,0,0,{rotx:.2f},{roty:.2f},{rotz:.2f},{DISTANCE}")

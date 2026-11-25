"""Shared sizes."""
IMG = 224          # model input size; 224 / 14 = 16 patches per side
PATCH = 14
GRID = IMG // PATCH
OUT = 112          # resolution of the label map sent back to Godot

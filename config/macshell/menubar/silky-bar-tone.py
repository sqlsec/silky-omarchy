#!/usr/bin/env python3
"""Read the wallpaper strip under the menu bar, one column every few logical pixels.

Prints {"w": <bar width>, "c": [[low, middle, high], ...]}: for each column, the
12th percentile, median and 88th percentile of the relative luminance in the bar
band, after the bar's own fill. The bar picks ink per control from these columns,
so a sample only has to be taken again when the wallpaper or the output changes.
"""

import json
import math
import subprocess
import sys
from pathlib import Path


def linear(channel):
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def luminance(red, green, blue):
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)


def sample(path, width, height, bar, fill):
    if not Path(path).is_file():
        raise ValueError("wallpaper is unavailable")
    # About two logical pixels per column: a hard edge in the wallpaper lands
    # between two controls instead of being smeared across one of them.
    columns = max(160, min(1024, round(width / 2)))
    rows = max(1, round(columns * height / width))
    band = min(rows, max(3, math.ceil(columns * bar / width)))
    data = subprocess.check_output(
        ["magick", f"{path}[0]", "-background", "black", "-alpha", "remove",
         "-colorspace", "sRGB", "-resize", f"{columns}x{rows}^",
         "-gravity", "center", "-extent", f"{columns}x{rows}",
         "-gravity", "north", "-crop", f"{columns}x{band}+0+0", "+repage",
         "-depth", "8", "rgb:-"],
        stderr=subprocess.DEVNULL,
        timeout=5,
    )
    if len(data) != columns * band * 3:
        raise ValueError("unexpected wallpaper sample size")
    levels = [luminance(*(channel / 255 * (1 - fill) + 0.1 * fill for channel in data[i:i + 3]))
              for i in range(0, len(data), 3)]
    result = []
    for column in range(columns):
        values = sorted(levels[row * columns + column] for row in range(band))
        last = len(values) - 1
        result.append([round(values[int(last * 0.12)], 4),
                       round(values[last // 2], 4),
                       round(values[math.ceil(last * 0.88)], 4)])
    return {"w": width, "c": result}


if __name__ == "__main__":
    try:
        path, width, height, bar, fill = sys.argv[1:6]
        print(json.dumps(sample(path, int(width), int(height), int(bar), float(fill)),
                         separators=(",", ":")))
    except (OSError, ValueError, subprocess.SubprocessError):
        sys.exit(1)

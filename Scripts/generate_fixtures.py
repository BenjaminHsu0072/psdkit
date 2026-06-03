#!/usr/bin/env python3
"""Generate PSD test fixtures using psd-tools (reference stack #1)."""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
    from psd_tools import PSDImage
except ImportError:
    print("Install: pip install psd-tools pillow", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Tests" / "PSDKitTests" / "Fixtures"
OUT.mkdir(parents=True, exist_ok=True)


def main() -> None:
    psd = PSDImage.new(mode="RGB", size=(8, 8), depth=8)
    psd.create_pixel_layer(
        Image.new("RGBA", (8, 8), (255, 0, 0, 128)),
        name="Red",
        top=0,
        left=0,
    )
    psd.save(OUT / "minimal-rgba.psd")

    psd2 = PSDImage.new(mode="RGB", size=(16, 16), depth=8)
    psd2.create_pixel_layer(
        Image.new("RGBA", (16, 16), (0, 255, 0, 255)),
        name="Green",
        top=0,
        left=0,
    )
    psd2.create_pixel_layer(
        Image.new("RGBA", (10, 10), (0, 0, 255, 255)),
        name="Blue",
        top=2,
        left=2,
        opacity=200,
    )
    psd2.save(OUT / "two-layers.psd")

    print(f"Wrote fixtures to {OUT}")


if __name__ == "__main__":
    main()

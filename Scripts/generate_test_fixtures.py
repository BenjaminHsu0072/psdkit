#!/usr/bin/env python3
"""
Generate PSD fixtures + golden manifest for PSDKit TDD.

Uses psd-tools (reference #1) to author files and compute expected metadata/pixels.
Run from repo root:

    pip install psd-tools pillow
    python3 Scripts/generate_test_fixtures.py

Outputs:
    Tests/PSDKitTests/Fixtures/*.psd
    Tests/PSDKitTests/Golden/manifest.json
    Tests/PSDKitTests/Golden/packbits.json
    Tests/PSDKitTests/Golden/rejections/*.psd (invalid files)
"""

from __future__ import annotations

import hashlib
import json
import struct
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from PIL import Image
    from psd_tools import PSDImage
    from psd_tools.constants import BlendMode, Compression
except ImportError:
    print("Install: pip install psd-tools pillow", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
FIXTURES_DIR = ROOT / "Tests" / "PSDKitTests" / "Fixtures"
GOLDEN_DIR = ROOT / "Tests" / "PSDKitTests" / "Golden"
RGBA_DIR = GOLDEN_DIR / "rgba"
REJECTIONS_DIR = GOLDEN_DIR / "rejections"


@dataclass
class LayerSpec:
    name: str
    left: int
    top: int
    size: tuple[int, int]
    color: tuple[int, int, int, int]
    opacity: int = 255
    visible: bool = True
    compression: Compression = Compression.RLE
    blend_mode: BlendMode = BlendMode.NORMAL


@dataclass
class DocSpec:
    id: str
    width: int
    height: int
    layers: list[LayerSpec]
    description: str
    tags: list[str]
    v1_read_supported: bool = True
    v1_write_roundtrip: str = "passthrough"  # passthrough | semantic | unsupported


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def rgba_from_layer_numpy(layer) -> bytes:
    """RGBA8888 row-major — matches PIL/topil (reference for PSDKit pixel tests)."""
    return layer.topil().convert("RGBA").tobytes()


def build_psd(spec: DocSpec, path: Path) -> None:
    psd = PSDImage.new(mode="RGB", size=(spec.width, spec.height), depth=8)
    for layer_spec in spec.layers:
        w, h = layer_spec.size
        pil = Image.new("RGBA", (w, h), layer_spec.color)
        layer = psd.create_pixel_layer(
            pil,
            name=layer_spec.name,
            top=layer_spec.top,
            left=layer_spec.left,
            compression=layer_spec.compression,
            opacity=layer_spec.opacity,
            blend_mode=layer_spec.blend_mode,
        )
        if not layer_spec.visible:
            layer.visible = False
    psd.save(path, encoding='utf-8')


def layer_entry(layer, index: int, fixture_id: str, skip_name: bool = False) -> dict[str, Any]:
    bbox = layer.bbox  # (left, top, right, bottom)
    pixels = rgba_from_layer_numpy(layer)
    rgba_name = f"{fixture_id}-layer{index}.rgba"
    if pixels:
        RGBA_DIR.mkdir(parents=True, exist_ok=True)
        (RGBA_DIR / rgba_name).write_bytes(pixels)
    return {
        "index": index,
        "name": layer.name,
        "kind": str(layer.kind),
        "bbox": {
            "left": bbox[0],
            "top": bbox[1],
            "right": bbox[2],
            "bottom": bbox[3],
        },
        "width": bbox[2] - bbox[0],
        "height": bbox[3] - bbox[1],
        "opacity": int(layer.opacity),
        "visible": bool(layer.visible),
        "blend_mode": (
            layer.blend_mode.decode("ascii", errors="replace")
            if isinstance(layer.blend_mode, bytes)
            else str(layer.blend_mode)
        ),
        "rgba_file": rgba_name if pixels else None,
        "pixel_byte_count": len(pixels),
        "skip_name_check": skip_name,
    }


def manifest_entry(spec: DocSpec, path: Path) -> dict[str, Any]:
    psd = PSDImage.open(path)
    layers = list(psd)
    file_bytes = path.read_bytes()
    composite = psd.numpy()
    composite_bytes = b""
    if composite is not None:
        import numpy as np

        comp = composite
        if comp.ndim == 2:
            h, w = comp.shape
            rgba = np.zeros((h, w, 4), dtype=np.uint8)
            v = (np.clip(comp, 0, 1) * 255).astype(np.uint8)
            rgba[:, :, :3] = np.stack([v, v, v], axis=-1)
            rgba[:, :, 3] = 255
        else:
            h, w, c = comp.shape
            rgba = np.zeros((h, w, 4), dtype=np.uint8)
            for i in range(min(3, c)):
                rgba[:, :, i] = (np.clip(comp[:, :, i], 0, 1) * 255).astype(np.uint8)
            rgba[:, :, 3] = 255 if c < 4 else (np.clip(comp[:, :, 3], 0, 1) * 255).astype(np.uint8)
        composite_bytes = rgba.astype(np.uint8).tobytes()

    return {
        "id": spec.id,
        "file": path.name,
        "description": spec.description,
        "tags": spec.tags,
        "v1_read_supported": spec.v1_read_supported,
        "v1_write_roundtrip": spec.v1_write_roundtrip,
        "file_sha256": sha256_bytes(file_bytes),
        "file_size": len(file_bytes),
        "header": {
            "width": psd.width,
            "height": psd.height,
            "channels": psd.channels,
            "depth": psd.depth,
            "version": 1,
            "color_mode": 3,
        },
        "layer_count": len(layers),
        "layers": [layer_entry(layer, i, spec.id, skip_name=(spec.id == "layer-name-unicode")) for i, layer in enumerate(layers)],
        "composite_sha256": sha256_bytes(composite_bytes) if composite_bytes else None,
    }


def all_specs() -> list[DocSpec]:
    """Coverage matrix for v1: 8-bit RGB bitmap layers without layer styles."""
    specs: list[DocSpec] = []

    def add(spec: DocSpec) -> None:
        specs.append(spec)

    # --- single layer ---
    add(
        DocSpec(
            id="single-rle-8x8",
            width=8,
            height=8,
            layers=[
                LayerSpec("SolidRed", 0, 0, (8, 8), (255, 0, 0, 255), compression=Compression.RLE)
            ],
            description="Single full-canvas layer, RLE compression",
            tags=["single", "rle", "8x8"],
        )
    )
    add(
        DocSpec(
            id="single-raw-8x8",
            width=8,
            height=8,
            layers=[
                LayerSpec("SolidBlue", 0, 0, (8, 8), (0, 0, 255, 255), compression=Compression.RAW)
            ],
            description="Single full-canvas layer, RAW compression",
            tags=["single", "raw", "8x8"],
        )
    )
    add(
        DocSpec(
            id="single-rgba-rle-16x16",
            width=16,
            height=16,
            layers=[
                LayerSpec(
                    "SemiRed",
                    0,
                    0,
                    (16, 16),
                    (255, 0, 0, 128),
                    compression=Compression.RLE,
                )
            ],
            description="Single layer with alpha channel, RLE",
            tags=["single", "rgba", "rle", "16x16"],
        )
    )
    add(
        DocSpec(
            id="canvas-1x1",
            width=1,
            height=1,
            layers=[LayerSpec("Px", 0, 0, (1, 1), (42, 84, 126, 255))],
            description="Minimum canvas size",
            tags=["edge", "1x1"],
        )
    )
    add(
        DocSpec(
            id="canvas-64x64",
            width=64,
            height=64,
            layers=[LayerSpec("Big", 0, 0, (64, 64), (10, 20, 30, 255))],
            description="Larger uniform layer (RLE friendly)",
            tags=["size", "64x64"],
        )
    )

    # --- multi layer ---
    add(
        DocSpec(
            id="two-layers",
            width=16,
            height=16,
            layers=[
                LayerSpec("Green", 0, 0, (16, 16), (0, 255, 0, 255)),
                LayerSpec("Blue", 2, 2, (10, 10), (0, 0, 255, 255), opacity=200),
            ],
            description="Two pixel layers with offset and opacity",
            tags=["multi", "opacity", "offset"],
        )
    )
    add(
        DocSpec(
            id="three-layers",
            width=24,
            height=24,
            layers=[
                LayerSpec("Back", 0, 0, (24, 24), (240, 240, 240, 255)),
                LayerSpec("Mid", 4, 4, (16, 16), (255, 128, 0, 255), opacity=220),
                LayerSpec("Front", 8, 8, (8, 8), (0, 0, 0, 255)),
            ],
            description="Three-layer stack",
            tags=["multi", "3"],
        )
    )
    add(
        DocSpec(
            id="mixed-compression",
            width=12,
            height=12,
            layers=[
                LayerSpec("RawLayer", 0, 0, (12, 12), (255, 255, 0, 255), compression=Compression.RAW),
                LayerSpec("RleLayer", 2, 2, (8, 8), (255, 0, 255, 255), compression=Compression.RLE),
            ],
            description="RAW + RLE layers in one document",
            tags=["multi", "raw", "rle"],
        )
    )

    # --- layer metadata ---
    add(
        DocSpec(
            id="layer-offset-10x10-on-32",
            width=32,
            height=32,
            layers=[LayerSpec("Small", 5, 7, (10, 10), (0, 128, 255, 255))],
            description="Layer smaller than canvas with offset bounds",
            tags=["bounds", "offset"],
        )
    )
    add(
        DocSpec(
            id="layer-opacity-50",
            width=8,
            height=8,
            layers=[LayerSpec("Half", 0, 0, (8, 8), (255, 0, 0, 255), opacity=128)],
            description="Layer opacity 128",
            tags=["opacity"],
        )
    )
    add(
        DocSpec(
            id="layer-hidden",
            width=8,
            height=8,
            layers=[
                LayerSpec("Visible", 0, 0, (8, 8), (0, 255, 0, 255)),
                LayerSpec("Hidden", 0, 0, (8, 8), (255, 0, 0, 255), visible=False),
            ],
            description="Second layer hidden in UI flags",
            tags=["visible", "flags"],
        )
    )
    add(
        DocSpec(
            id="layer-name-unicode",
            width=8,
            height=8,
            layers=[LayerSpec("图层α", 0, 0, (8, 8), (128, 64, 192, 255))],
            description="Unicode layer name (luni when saved by psd-tools)",
            tags=["unicode", "name"],
        )
    )

    # --- patterns for RLE stress ---
    add(
        DocSpec(
            id="rle-gradient-horizontal",
            width=32,
            height=8,
            layers=[
                LayerSpec(
                    "Gradient",
                    0,
                    0,
                    (32, 8),
                    (0, 0, 0, 255),  # placeholder; replaced below
                    compression=Compression.RLE,
                )
            ],
            description="Horizontal gradient (mixed RLE runs)",
            tags=["rle", "gradient"],
        )
    )

    return specs


def build_gradient_layer_image(w: int, h: int) -> Image.Image:
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for x in range(w):
        v = int(255 * x / max(w - 1, 1))
        for y in range(h):
            px[x, y] = (v, v, v, 255)
    return img


def build_gradient_psd(spec: DocSpec, path: Path) -> None:
    psd = PSDImage.new(mode="RGB", size=(spec.width, spec.height), depth=8)
    layer_spec = spec.layers[0]
    w, h = layer_spec.size
    pil = build_gradient_layer_image(w, h)
    psd.create_pixel_layer(
        pil,
        name=layer_spec.name,
        top=layer_spec.top,
        left=layer_spec.left,
        compression=layer_spec.compression,
    )
    psd.save(path, encoding='utf-8')


def generate_packbits_vectors() -> list[dict[str, Any]]:
    """Vectors aligned with psd-tools compression/rle.py behavior."""
    from psd_tools.compression.rle import decode, encode

    cases = []
    for name, raw in [
        ("empty", b""),
        ("single", b"\xab"),
        ("solid100", bytes([0xAB]) * 100),
        ("literal50", bytes([i % 251 for i in range(50)])),
        ("alt_run", b"\x00" * 20 + b"\xff" * 20),
    ]:
        encoded = encode(raw)
        decoded = decode(encoded, len(raw))
        cases.append(
            {
                "name": name,
                "raw_hex": raw.hex(),
                "encoded_hex": encoded.hex(),
                "size": len(raw),
            }
        )
    return cases


def write_rejection_fixtures() -> list[dict[str, Any]]:
    """Minimal invalid PSDs for negative tests."""
    REJECTIONS_DIR.mkdir(parents=True, exist_ok=True)
    entries = []

    # Wrong signature
    bad_sig = bytearray(build_valid_header_bytes(8, 8))
    bad_sig[0:4] = b"XXXX"
    path = REJECTIONS_DIR / "reject-bad-signature.psd"
    path.write_bytes(attach_empty_sections(bytes(bad_sig)))
    entries.append(
        {
            "id": "reject-bad-signature",
            "file": "rejections/reject-bad-signature.psd",
            "expected_error": "invalidSignature",
        }
    )

    # Version 2 (PSB-style version field) — v1 reader should reject
    bad_ver = bytearray(build_valid_header_bytes(8, 8))
    struct.pack_into(">H", bad_ver, 4, 2)
    path = REJECTIONS_DIR / "reject-version-2.psd"
    path.write_bytes(attach_empty_sections(bytes(bad_ver)))
    entries.append(
        {
            "id": "reject-version-2",
            "file": "rejections/reject-version-2.psd",
            "expected_error": "unsupportedVersion",
        }
    )

    # 16-bit depth
    bad_depth = bytearray(build_valid_header_bytes(8, 8))
    struct.pack_into(">H", bad_depth, 22, 16)
    path = REJECTIONS_DIR / "reject-depth-16.psd"
    path.write_bytes(attach_empty_sections(bytes(bad_depth)))
    entries.append(
        {
            "id": "reject-depth-16",
            "file": "rejections/reject-depth-16.psd",
            "expected_error": "unsupportedBitDepth",
        }
    )

    # CMYK color mode
    bad_cm = bytearray(build_valid_header_bytes(8, 8))
    struct.pack_into(">H", bad_cm, 24, 4)
    path = REJECTIONS_DIR / "reject-cmyk.psd"
    path.write_bytes(attach_empty_sections(bytes(bad_cm)))
    entries.append(
        {
            "id": "reject-cmyk",
            "file": "rejections/reject-cmyk.psd",
            "expected_error": "unsupportedColorMode",
        }
    )

    return entries


def build_valid_header_bytes(width: int, height: int, channels: int = 3) -> bytes:
    buf = bytearray(26)
    buf[0:4] = b"8BPS"
    struct.pack_into(">H", buf, 4, 1)
  # reserved 6 bytes at 6..11
    struct.pack_into(">H", buf, 12, channels)
    struct.pack_into(">I", buf, 14, height)
    struct.pack_into(">I", buf, 18, width)
    struct.pack_into(">H", buf, 22, 8)
    struct.pack_into(">H", buf, 24, 3)
    return bytes(buf)


def attach_empty_sections(header: bytes) -> bytes:
    """Header + empty color/resources/layer + minimal raw composite."""
    out = bytearray(header)
    out += struct.pack(">I", 0)  # color mode
    out += struct.pack(">I", 0)  # image resources
    out += struct.pack(">I", 0)  # layer and mask
    out += struct.pack(">H", 0)  # composite raw compression
    # minimal 8*8*3 composite if 8x8 — caller uses matching header size
    return bytes(out)


def main() -> None:
    RGBA_DIR.mkdir(parents=True, exist_ok=True)
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)
    GOLDEN_DIR.mkdir(parents=True, exist_ok=True)

    specs = all_specs()
    fixtures_manifest = []

    for spec in specs:
        path = FIXTURES_DIR / f"{spec.id}.psd"
        if spec.id == "rle-gradient-horizontal":
            build_gradient_psd(spec, path)
        else:
            build_psd(spec, path)
        fixtures_manifest.append(manifest_entry(spec, path))
        print("wrote", path.name)

    packbits = generate_packbits_vectors()
    (GOLDEN_DIR / "packbits.json").write_text(
        json.dumps({"version": 1, "cases": packbits}, indent=2) + "\n",
        encoding="utf-8",
    )

    rejections = write_rejection_fixtures()

    manifest = {
        "version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generator": "Scripts/generate_test_fixtures.py",
        "reference": "psd-tools",
        "fixtures": fixtures_manifest,
        "rejections": rejections,
        "coverage_tags": sorted({t for s in specs for t in s.tags}),
    }
    (GOLDEN_DIR / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    # Legacy aliases used by early tests
    legacy = {
        "minimal-rgba": "single-rgba-rle-16x16",
        "two-layers": "two-layers",
    }
    for old, new in legacy.items():
        src = FIXTURES_DIR / f"{new}.psd"
        dst = FIXTURES_DIR / f"{old}.psd"
        if src.exists():
            dst.write_bytes(src.read_bytes())

    print(f"\nGenerated {len(fixtures_manifest)} fixtures, {len(rejections)} rejection files")
    print(f"Manifest: {GOLDEN_DIR / 'manifest.json'}")


if __name__ == "__main__":
    main()

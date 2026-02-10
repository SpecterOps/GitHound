#!/usr/bin/env python3
"""
Render PNG node icons for GitHound's BloodHound OpenGraph model.

Reads model.json and generates a PNG icon for each custom node type.
Each icon is a colored circle with a black border and a centered black
Font Awesome icon.

Dependencies (pure Python — no native C libraries required):
    pip install Pillow svgpathtools numpy requests

Usage:
    python3 scripts/render_icons.py [--size 220] [--scale 0.55]
"""

import argparse
import json
import re
import sys
from pathlib import Path

# ── Dependency check ────────────────────────────────────────────────
_missing = []
try:
    from PIL import Image, ImageDraw
except ImportError:
    _missing.append("Pillow")
try:
    from svgpathtools import parse_path
except ImportError:
    _missing.append("svgpathtools")
try:
    import requests
except ImportError:
    _missing.append("requests")

if _missing:
    print(
        "Missing Python dependencies: " + ", ".join(_missing),
        file=sys.stderr,
    )
    print(
        "Install with:  pip3 install Pillow svgpathtools numpy requests",
        file=sys.stderr,
    )
    sys.exit(1)

# ── Constants ───────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
MODEL_JSON = REPO_ROOT / "model.json"
OUTPUT_DIR = REPO_ROOT / "Documentation" / "images"

FA_SVG_URL = (
    "https://raw.githubusercontent.com/FortAwesome/Font-Awesome"
    "/refs/heads/7.x/svgs/solid/{name}.svg"
)

# Caches
_svg_cache: dict[str, str] = {}

# Points per unit length when sampling bezier curves
SAMPLES_PER_UNIT = 0.15


def fetch_icon_svg(icon_name: str) -> str:
    """Download a Font Awesome SVG and return its text."""
    if icon_name in _svg_cache:
        return _svg_cache[icon_name]

    url = FA_SVG_URL.format(name=icon_name)
    resp = requests.get(url, timeout=30)
    resp.raise_for_status()
    text = resp.text
    _svg_cache[icon_name] = text
    return text


def parse_svg_viewbox(svg_text: str) -> tuple[float, float, float, float]:
    """Extract viewBox from SVG text."""
    m = re.search(r'viewBox="([^"]+)"', svg_text)
    if not m:
        raise ValueError("No viewBox found in SVG")
    parts = m.group(1).split()
    return tuple(float(x) for x in parts)  # type: ignore


def parse_svg_paths(svg_text: str) -> list[str]:
    """Extract all <path d="..."> data strings from SVG text."""
    return re.findall(r'<path[^>]*\bd="([^"]+)"', svg_text)


def path_to_polygons(
    d: str,
    target_size: int,
    vb_x: float,
    vb_y: float,
    vb_w: float,
    vb_h: float,
) -> list[list[tuple[float, float]]]:
    """
    Convert an SVG path 'd' attribute into a list of polygon point lists.

    Each sub-path (separated by M/m commands) becomes a separate polygon.
    Bezier curves are sampled into line segments.
    Coordinates are scaled from viewBox space to target pixel space,
    centered in target_size.
    """
    path = parse_path(d)

    # Compute scale to fit viewBox into target_size, preserving aspect ratio
    scale = target_size / max(vb_w, vb_h)
    # Center offset
    ox = (target_size - vb_w * scale) / 2 - vb_x * scale
    oy = (target_size - vb_h * scale) / 2 - vb_y * scale

    polygons: list[list[tuple[float, float]]] = []
    current_poly: list[tuple[float, float]] = []

    for seg in path:
        # Determine number of sample points based on segment length
        seg_len = seg.length()
        n_points = max(2, int(seg_len * SAMPLES_PER_UNIT))

        start_pt = seg.point(0)
        sx = start_pt.real * scale + ox
        sy = start_pt.imag * scale + oy

        # Check if this is a new sub-path (discontinuity)
        if current_poly and (
            abs(sx - current_poly[-1][0]) > 1 or abs(sy - current_poly[-1][1]) > 1
        ):
            if len(current_poly) >= 3:
                polygons.append(current_poly)
            current_poly = []

        if not current_poly:
            current_poly.append((sx, sy))

        # Sample points along the segment
        for i in range(1, n_points + 1):
            t = i / n_points
            pt = seg.point(t)
            px = pt.real * scale + ox
            py = pt.imag * scale + oy
            current_poly.append((px, py))

    if len(current_poly) >= 3:
        polygons.append(current_poly)

    return polygons


def render_icon(
    icon_name: str,
    fill_color: str,
    image_size: int = 220,
    icon_scale: float = 0.55,
    border_width: int = 0,
) -> Image.Image:
    """
    Render a single node icon as a Pillow RGBA Image.

    1. Draw a filled circle in fill_color with a black border.
    2. Parse the Font Awesome SVG path and render as filled polygons.
    3. Return the composited image.
    """
    if border_width == 0:
        border_width = max(2, int(image_size * 0.054))

    # ── Supersample for antialiasing ────────────────────────────────
    ss = 4
    ss_size = image_size * ss
    ss_border = border_width * ss

    canvas = Image.new("RGBA", (ss_size, ss_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    center = ss_size // 2
    radius = center - ss_border // 2

    # Filled circle with black border
    bbox = [
        center - radius,
        center - radius,
        center + radius,
        center + radius,
    ]
    draw.ellipse(bbox, fill=fill_color, outline="black", width=ss_border)

    # ── Parse and render SVG icon ───────────────────────────────────
    svg_text = fetch_icon_svg(icon_name)
    vb = parse_svg_viewbox(svg_text)
    path_strings = parse_svg_paths(svg_text)

    icon_target = int(ss_size * icon_scale)
    icon_offset = (ss_size - icon_target) // 2

    for d in path_strings:
        polygons = path_to_polygons(d, icon_target, vb[0], vb[1], vb[2], vb[3])
        for poly in polygons:
            # Offset polygons to center on canvas
            shifted = [(x + icon_offset, y + icon_offset) for x, y in poly]
            if len(shifted) >= 3:
                draw.polygon(shifted, fill="black")

    # ── Downsample ──────────────────────────────────────────────────
    final = canvas.resize((image_size, image_size), Image.LANCZOS)
    return final


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Render PNG node icons from model.json"
    )
    parser.add_argument(
        "--size",
        type=int,
        default=220,
        help="Output image size in pixels (default: 220)",
    )
    parser.add_argument(
        "--scale",
        type=float,
        default=0.55,
        help="Icon scale relative to image size (default: 0.55)",
    )
    args = parser.parse_args()

    if not MODEL_JSON.exists():
        print(f"Error: {MODEL_JSON} not found", file=sys.stderr)
        sys.exit(1)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    with open(MODEL_JSON) as f:
        model = json.load(f)

    custom_types = model.get("custom_types", {})
    if not custom_types:
        print("No custom_types found in model.json", file=sys.stderr)
        sys.exit(1)

    print(f"[*] Rendering {len(custom_types)} node icons ({args.size}x{args.size}px)")

    for node_name in sorted(custom_types):
        node_def = custom_types[node_name]
        icon_info = node_def.get("icon", {})
        icon_type = icon_info.get("type", "")
        icon_name = icon_info.get("name", "")
        icon_color = icon_info.get("color", "#888888")

        if icon_type != "font-awesome":
            print(f"  [!] Skipping {node_name}: unsupported icon type '{icon_type}'")
            continue

        try:
            img = render_icon(
                icon_name=icon_name,
                fill_color=icon_color,
                image_size=args.size,
                icon_scale=args.scale,
            )
            out_path = OUTPUT_DIR / f"{node_name}.png"
            img.save(out_path, "PNG")
            print(f"  [+] {out_path.name}")
        except Exception as e:
            print(f"  [!] Skipping {node_name}: {e}")

    print("[+] Done.")


if __name__ == "__main__":
    main()

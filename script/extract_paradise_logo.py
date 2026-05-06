"""
One-off helper: unwrap the Paradise Energy Solutions logo from the
~1 MB "footer" SVG into a small PNG ready to ship as a tenant asset.

The source SVG is essentially packaging: 4 base64-embedded PNGs (two
grayscale alpha masks, two RGB color images) sitting under <feColorMatrix>
filter chains that recolor and luminance-to-alpha them at render time.
For our purposes we don't need the runtime filter math — we just need the
final composited bitmap. So we pull the RGB image, attach the paired
grayscale image as its alpha channel, crop to the actual content bbox,
downscale for the sidebar (h-10 = 40px → 2x = 80px tall, our render cap),
and write an optimized PNG.

Output target: <= 60 KB at public/branding/paradise.png with transparent
background. If output exceeds 60 KB the script aborts so we notice when
quality drift slips in.

Run from repo root:
  python3 script/extract_paradise_logo.py
"""

from __future__ import annotations

import base64
import io
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path("/Users/lukegill/Downloads/pse-new-logo-footer.svg")
DST = Path("public/branding/paradise.png")

TARGET_HEIGHT_PX = 80
MAX_BYTES = 60 * 1024


def extract_embedded_pngs(svg_text: str) -> list[Image.Image]:
    """Return every base64-encoded PNG carried by an <image> tag, in source order."""
    pattern = re.compile(
        r'<image\b[^>]*?(?:href|xlink:href)="data:image/png;base64,'
        r'([A-Za-z0-9+/=]+)"',
        re.S,
    )
    images: list[Image.Image] = []
    for m in pattern.finditer(svg_text):
        raw = base64.b64decode(m.group(1))
        images.append(Image.open(io.BytesIO(raw)))
    return images


def composite_rgb_with_alpha(rgb: Image.Image, alpha_src: Image.Image) -> Image.Image:
    """Build an RGBA from an RGB color layer + a grayscale layer used as alpha.

    Source convention (verified by sampling pixel values from the SVG's
    embedded PNGs): the RGB image is the colored logo composited onto a
    black background; the grayscale image is a standard alpha mask where
    background = 0 (transparent) and foreground = 255 (opaque). The SVG's
    runtime feColorMatrix filter writes the grayscale's luminance directly
    into alpha, so we use the mask as-is rather than inverting it.

    Anti-aliased edges in the RGB layer have already been blended against
    black, so a naive RGBA assembly leaves a sooty fringe on light surfaces.
    We unpremultiply against black at edge pixels — same trick as
    `strip_logo_background.py` — to recover the original foreground color.
    """
    rgb_arr = np.array(rgb.convert("RGB"), dtype=np.float32)
    alpha = np.array(alpha_src.convert("L"), dtype=np.float32)

    safe_alpha = np.where(alpha > 0, alpha, 1.0)
    scale = (255.0 / safe_alpha)[:, :, np.newaxis]
    rgb_unpremul = np.clip(rgb_arr * scale, 0, 255)

    out = np.dstack([rgb_unpremul, alpha]).astype(np.uint8)
    return Image.fromarray(out, mode="RGBA")


def crop_to_alpha_bbox(img: Image.Image) -> Image.Image:
    """Trim transparent padding so the saved logo sits flush in its viewport."""
    bbox = img.getbbox()  # bbox of the alpha (non-transparent) region
    return img.crop(bbox) if bbox else img


def downscale_to_height(img: Image.Image, target_h: int) -> Image.Image:
    """Lanczos-resample so the artwork's height matches our 2x sidebar cap."""
    if img.height <= target_h:
        return img
    ratio = target_h / img.height
    new_w = max(1, round(img.width * ratio))
    return img.resize((new_w, target_h), Image.LANCZOS)


def main() -> None:
    if not SRC.exists():
        sys.exit(f"missing source SVG: {SRC}")

    svg_text = SRC.read_text(encoding="utf-8", errors="replace")
    embedded = extract_embedded_pngs(svg_text)

    # The source has two pairs of (grayscale mask, RGB color). Take the first
    # RGB image (mode='RGB') and the first grayscale image (mode='L') to
    # rebuild the composited bitmap. If the layout ever changes, fall back to
    # luminance-derived alpha on the RGB image alone.
    rgb_img = next((i for i in embedded if i.mode == "RGB"), None)
    gray_img = next((i for i in embedded if i.mode == "L"), None)
    if rgb_img is None:
        sys.exit(f"no RGB <image> found in {SRC}")

    if gray_img is not None and gray_img.size == rgb_img.size:
        composed = composite_rgb_with_alpha(rgb_img, gray_img)
    else:
        # Fallback: derive alpha from RGB luminance (bright bg → transparent).
        rgb_arr = np.array(rgb_img.convert("RGB"), dtype=np.float32)
        lum = (
            0.2126 * rgb_arr[:, :, 0]
            + 0.7152 * rgb_arr[:, :, 1]
            + 0.0722 * rgb_arr[:, :, 2]
        )
        alpha = np.clip(255 - lum, 0, 255).astype(np.uint8)
        composed = Image.fromarray(
            np.dstack([rgb_arr.astype(np.uint8), alpha]),
            mode="RGBA",
        )

    cropped = crop_to_alpha_bbox(composed)
    sized = downscale_to_height(cropped, TARGET_HEIGHT_PX)

    DST.parent.mkdir(parents=True, exist_ok=True)
    sized.save(DST, format="PNG", optimize=True)

    size_bytes = DST.stat().st_size
    print(f"wrote {DST} ({sized.size[0]}x{sized.size[1]} RGBA, {size_bytes:,} bytes)")
    if size_bytes > MAX_BYTES:
        sys.exit(
            f"output exceeds {MAX_BYTES:,} byte ceiling — re-tune quality before committing"
        )


if __name__ == "__main__":
    main()

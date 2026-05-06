"""
One-off helper: strip the solid-black background from the SolarIQ+ logo PNG.

The source export is an opaque PNG (logo composited on black). We need a
PNG with a transparent background so the logo reads on the app's light
surfaces. We do this by deriving alpha from luminance, then reversing the
black-composite math so anti-aliased edges don't fringe dark.

Run from repo root:
  python3 script/strip_logo_background.py
"""

from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path("app/assets/images/solar_iq_logo.png")
DST = SRC  # overwrite in place


def strip_black(img: Image.Image) -> Image.Image:
    arr = np.array(img.convert("RGBA"), dtype=np.float32)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]

    # Brightness proxy — pure-black bg pixels are 0 across all channels;
    # any colored/gray foreground pixel has at least one channel > 0.
    maxc = np.maximum(np.maximum(r, g), b)

    # Smooth alpha ramp: maxc <= LOW => transparent, maxc >= HIGH => opaque.
    # A narrow band keeps anti-aliased edges soft without dragging mid-gray
    # body pixels (the "SOLAR" wordmark sits around RGB 100+) into translucency.
    LOW, HIGH = 6.0, 28.0
    alpha = np.clip((maxc - LOW) * 255.0 / (HIGH - LOW), 0.0, 255.0)

    # Unpremultiply against black: the source pixel is fg * (alpha/255), so
    # the original fg color is source / (alpha/255). Without this, dark anti-
    # aliased edges of the gray wordmark would render as a sooty fringe on a
    # light background.
    safe_alpha = np.where(alpha > 0, alpha, 1.0)
    scale = 255.0 / safe_alpha
    out = np.zeros_like(arr)
    out[:, :, 0] = np.clip(r * scale, 0, 255)
    out[:, :, 1] = np.clip(g * scale, 0, 255)
    out[:, :, 2] = np.clip(b * scale, 0, 255)
    out[:, :, 3] = alpha

    return Image.fromarray(out.astype(np.uint8), "RGBA")


def main() -> None:
    src_img = Image.open(SRC)
    out_img = strip_black(src_img)
    out_img.save(DST, format="PNG", optimize=True)
    print(f"wrote {DST} ({out_img.size[0]}x{out_img.size[1]} RGBA)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Compare a screenshot against the wireframe sidebar: SSIM, edge SSIM, overlay, diff."""
import pathlib
import sys

import numpy as np
from PIL import Image, ImageFilter

CROP_TOP = 177  # 59pt status bar at 3x, excluded from both sides
WIDTH = 990  # 330pt sidebar at 3x


def box(value: np.ndarray, k: int) -> np.ndarray:
    pad = k // 2
    padded = np.pad(value, pad, mode="reflect")
    cumulative = np.cumsum(np.cumsum(padded, 0), 1)
    cumulative = np.pad(cumulative, ((1, 0), (1, 0)))
    height, width = value.shape
    window = (
        cumulative[k : k + height, k : k + width]
        - cumulative[0:height, k : k + width]
        - cumulative[k : k + height, 0:width]
        + cumulative[0:height, 0:width]
    )
    return window / (k * k)


def ssim(a: np.ndarray, b: np.ndarray) -> float:
    c1 = (0.01 * 255) ** 2
    c2 = (0.03 * 255) ** 2
    k = 11
    ma, mb = box(a, k), box(b, k)
    maa, mbb, mab = box(a * a, k), box(b * b, k), box(a * b, k)
    va, vb, vab = maa - ma * ma, mbb - mb * mb, mab - ma * mb
    score = ((2 * ma * mb + c1) * (2 * vab + c2)) / (
        (ma * ma + mb * mb + c1) * (va + vb + c2)
    )
    return float(score.mean())


def edges(image: Image.Image) -> np.ndarray:
    return np.asarray(image.filter(ImageFilter.FIND_EDGES), dtype=np.float64)


def crop(image: Image.Image) -> Image.Image:
    return image.convert("RGB").crop((0, CROP_TOP, WIDTH, image.height))


def main() -> None:
    ref_path, mine_path, out_dir = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
    ref, mine = crop(Image.open(ref_path)), crop(Image.open(mine_path))
    if mine.size != ref.size:
        mine = mine.resize(ref.size, Image.LANCZOS)

    ref_gray = np.asarray(ref.convert("L"), dtype=np.float64)
    mine_gray = np.asarray(mine.convert("L"), dtype=np.float64)

    print(f"size {ref.size[0]}x{ref.size[1]}")
    print(f"SSIM  {ssim(ref_gray, mine_gray):.4f}")
    print(f"edge  {ssim(edges(ref.convert('L')), edges(mine.convert('L'))):.4f}")

    out_dir.mkdir(parents=True, exist_ok=True)
    Image.blend(ref, mine, 0.5).save(out_dir / "diff_overlay.png")
    delta = np.abs(ref_gray - mine_gray).astype(np.uint8)
    Image.fromarray(delta).save(out_dir / "diff_abs.png")
    ref.save(out_dir / "ref_sidebar.png")
    mine.save(out_dir / "mine_sidebar.png")


if __name__ == "__main__":
    main()

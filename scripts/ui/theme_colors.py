#!/usr/bin/env python3
"""Programmatic color fidelity check: measures semantic elements in our
simulator screenshots and compares them to the reference tokens via
CIEDE2000.

Reference values were measured programmatically from IMG_2361..2364 in
/srv/devops/artifacts/chat-theme-reference (ChatGPT light/dark chat and
sidebar). Elements without a reference counterpart are skipped.

Usage: theme_colors.py <chat-light.png> <chat-dark.png> [sidebar-light.png]
"""
import sys
import numpy as np
from PIL import Image

W, H = 1179, 2556

REFERENCE = {
    "light": {
        "bg": "#FFFFFF",
        "user_bubble": "#F3F3F3",
        "assistant_text": "#0D0D0D",
        "composer": "#F7F7F7",
        "send_button": "#191919",
        "list_marker": "#888888",
    },
    "dark": {
        "bg": "#000000",
        "user_bubble": "#414141",
        "assistant_text": "#FFFFFF",
        "composer": "#151515",
        "send_button": "#F3F3F3",
        "list_marker": "#8F8F8F",
    },
}


def hex_rgb(h):
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))


def lab(h):
    r, g, b = [c / 255.0 for c in hex_rgb(h)]

    def f(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = f(r), f(g), f(b)
    x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
    y = r * 0.2126 + g * 0.7152 + b * 0.0722
    z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883

    def g2(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    fx, fy, fz = g2(x), g2(y), g2(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def ciede2000(l1, l2):
    import math
    L1, a1, b1 = l1
    L2, a2, b2 = l2
    C1, C2 = math.hypot(a1, b1), math.hypot(a2, b2)
    Cavg = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cavg ** 7 / (Cavg ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360 if (a1p or b1) else 0
    h2p = math.degrees(math.atan2(b2, a2p)) % 360 if (a2p or b2) else 0
    dL, dC = L2 - L1, C2p - C1p
    if C1p * C2p == 0:
        dh = 0.0
    elif abs(h2p - h1p) <= 180:
        dh = h2p - h1p
    elif h2p - h1p > 180:
        dh = h2p - h1p - 360
    else:
        dh = h2p - h1p + 360
    dH = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dh / 2))
    Lavg, Cavgp = (L1 + L2) / 2, (C1p + C2p) / 2
    if C1p * C2p == 0:
        havg = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        havg = (h1p + h2p) / 2
    elif h2p - h1p > 180:
        havg = (h1p + h2p + 360) / 2
    else:
        havg = (h1p + h2p - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(havg - 30))
         + 0.24 * math.cos(math.radians(2 * havg))
         + 0.32 * math.cos(math.radians(3 * havg + 6))
         - 0.20 * math.cos(math.radians(4 * havg - 63)))
    dtheta = 30 * math.exp(-(((havg - 275) / 25) ** 2))
    RC = 2 * math.sqrt(Cavgp ** 7 / (Cavgp ** 7 + 25 ** 7))
    SL = 1 + 0.015 * (Lavg - 50) ** 2 / math.sqrt(20 + (Lavg - 50) ** 2)
    SC = 1 + 0.045 * Cavgp
    SH = 1 + 0.015 * Cavgp * T
    RT = -math.sin(math.radians(2 * dtheta)) * RC
    return math.sqrt(max(0.0, (dL / SL) ** 2 + (dC / SC) ** 2 + (dH / SH) ** 2))


def mode_color(im, x, y, w, h):
    reg = im[y:y + h, x:x + w].reshape(-1, 3)
    vals, counts = np.unique(reg, axis=0, return_counts=True)
    return tuple(int(v) for v in vals[np.argmax(counts)])


def ink_color(im, x, y, w, h, dark):
    reg = im[y:y + h, x:x + w].reshape(-1, 3)
    lum = reg.sum(axis=1)
    pick = reg[lum <= np.percentile(lum, 1)] if not dark else reg[lum >= np.percentile(lum, 99)]
    return tuple(int(v) for v in np.median(pick, axis=0))


def measure_chat(path, dark):
    im = np.array(Image.open(path).convert("RGB")).astype(int)
    out = {"bg": mode_color(im, 30, 1150, 30, 30)}
    # user bubble: scan right half for the tall flat band whose mode color
    # differs from the background; the bubble is the only such wide band.
    band = None
    y = 300
    while y < 2300:
        c = mode_color(im, 760, y, 340, 8)
        if c != out["bg"] and np.abs(np.array(c) - np.array(out["bg"])).sum() > 24:
            y2 = y
            while y2 < 2300:
                c2 = mode_color(im, 760, y2, 340, 8)
                if np.abs(np.array(c2) - np.array(c)).sum() > 24:
                    break
                y2 += 8
            if y2 - y >= 60:
                band = (y, y2, c)
                break
            y = y2 + 8
        else:
            y += 8
    out["user_bubble"] = band[2] if band else mode_color(im, 800, 640, 200, 160)
    out["assistant_text"] = ink_color(im, 25, 750, 1120, 60, dark)
    out["composer"] = mode_color(im, 200, 2360, 160, 30)
    out["send_button"] = ink_color(im, 1040, 2290, 90, 70, dark)
    out["list_marker"] = ink_color(im, 50, 1245, 26, 40, dark)
    return out


def main():
    chat_light, chat_dark = sys.argv[1], sys.argv[2]
    results = []
    for mode, path, dark in (("light", chat_light, False), ("dark", chat_dark, True)):
        got = measure_chat(path, dark)
        for element, ref_hex in REFERENCE[mode].items():
            got_hex = "#%02X%02X%02X" % got[element]
            de = ciede2000(lab(ref_hex), lab(got_hex))
            status = "PASS" if de < 3 else ("WARN" if de < 6 else "FAIL")
            results.append((mode, element, ref_hex, got_hex, de, status))

    fails = sum(1 for r in results if r[5] == "FAIL")
    print(f"{'mode':6} {'element':15} {'ref':8} {'app':8} {'dE00':>6} status")
    for mode, element, ref, got, de, status in results:
        print(f"{mode:6} {element:15} {ref:8} {got:8} {de:6.2f} {status}")
    print(f"\n{fails} failing")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()

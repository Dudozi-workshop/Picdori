#!/usr/bin/env python3
"""Check generated Picdori launcher resources in both native Flutter runners.

The tests check tangible resources only; actual rendering on iOS/Android
devices remains part of the final integrated acceptance pass.
"""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


def png_dimensions(path: Path) -> tuple[int, int]:
    if not path.exists():
        raise SystemExit(f"Missing launcher PNG: {path}")
    with path.open("rb") as stream:
        header = stream.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise SystemExit(f"Invalid launcher PNG: {path}")
    return struct.unpack(">II", header[16:24])


for relative in (
    "assets/icons/picdori_launcher.png",
    "assets/icons/picdori_adaptive_foreground.png",
):
    path = ROOT / relative
    if png_dimensions(path) != (1024, 1024):
        raise SystemExit(f"Launcher input is not 1024px: {path}")

ios_dir = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
ios_icons = list(ios_dir.glob("*.png"))
if len(ios_icons) < 3:
    raise SystemExit("iOS AppIcon.appiconset was not populated.")
if not any(png_dimensions(path) == (1024, 1024) for path in ios_icons):
    raise SystemExit("No 1024px iOS store icon was generated.")

res_dir = ROOT / "android/app/src/main/res"
android_icons = list(res_dir.glob("mipmap-*/ic_launcher.png"))
if len(android_icons) < 3:
    raise SystemExit("Android launcher mipmaps were not generated.")
if not (res_dir / "mipmap-anydpi-v26/ic_launcher.xml").exists():
    raise SystemExit("Android adaptive launcher icon XML is missing.")

print("Picdori Android/iOS launcher assets verified.")

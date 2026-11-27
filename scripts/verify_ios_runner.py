#!/usr/bin/env python3
"""Check generated native iOS runner before building the simulator target."""
from pathlib import Path
import plistlib
import struct

root = Path(__file__).resolve().parents[1]
ios = root / "ios"
plist_path = ios / "Runner/Info.plist"
project_path = ios / "Runner.xcodeproj/project.pbxproj"

with plist_path.open("rb") as stream:
    settings = plistlib.load(stream)
if settings.get("CFBundleDisplayName") != "픽도리":
    raise SystemExit("Unexpected iOS display name.")
if settings.get("CFBundleName") != "Picdori":
    raise SystemExit("Unexpected iOS bundle name.")
for key in ("NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"):
    if not settings.get(key):
        raise SystemExit(f"Missing iOS permission reason: {key}")
for key in ("UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace"):
    if settings.get(key) is not True:
        raise SystemExit(f"Missing iOS Files app visibility: {key}")
if "com.dudozi.picdori" not in project_path.read_text(encoding="utf-8"):
    raise SystemExit("iOS bundle ID mismatch.")

app_icons = list((ios / "Runner/Assets.xcassets/AppIcon.appiconset").glob("*.png"))
if not app_icons:
    raise SystemExit("iOS launcher images not generated.")
def is_1024(path: Path) -> bool:
    data = path.read_bytes()[:24]
    return data[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", data[16:24]) == (1024, 1024)
if not any(is_1024(path) for path in app_icons):
    raise SystemExit("iOS store icon (1024 x 1024) missing.")

print("Picdori iOS runner identity and approved mascot icon verified.")

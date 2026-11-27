#!/usr/bin/env python3
"""Idempotently configure iOS photo library permission strings.

Run after: flutter create . --project-name picdori --org com.dudozi --platforms android,ios
"""
from pathlib import Path
import plistlib

plist_path = Path(__file__).resolve().parents[1] / "ios/Runner/Info.plist"
if not plist_path.exists():
    raise SystemExit("Missing ios/Runner/Info.plist. Run flutter create first.")

with plist_path.open("rb") as f:
    plist = plistlib.load(f)

plist["CFBundleDisplayName"] = "픽도리"
plist["CFBundleName"] = "Picdori"

plist["NSPhotoLibraryUsageDescription"] = (
    "픽도리가 사진을 선택하고 원하는 크기와 용량으로 변환하기 위해 사용합니다."
)
plist["NSPhotoLibraryAddUsageDescription"] = (
    "픽도리에서 변환한 사진을 사용자의 사진첩에 저장하기 위해 사용합니다."
)

# Expose files saved to the app Documents directory through iOS Files
# when users choose on-device storage; unrelated photo permissions unchanged.
plist["UIFileSharingEnabled"] = True
plist["LSSupportsOpeningDocumentsInPlace"] = True

with plist_path.open("wb") as f:
    plistlib.dump(plist, f, sort_keys=False)
print(f"Updated: {plist_path}")

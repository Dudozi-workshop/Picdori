#!/usr/bin/env python3
"""Verify Flutter, Android and iOS identities in the generated project."""
from pathlib import Path
import plistlib
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
android = root / "android/app/src/main/AndroidManifest.xml"
ios = root / "ios/Runner/Info.plist"
project = root / "ios/Runner.xcodeproj/project.pbxproj"

application = ET.parse(android).getroot().find("application")
if application is None:
    raise SystemExit("Missing Android application element.")
name = application.get("{http://schemas.android.com/apk/res/android}label")
if name != "픽도리":
    raise SystemExit(f"Unexpected Android launcher label: {name!r}")

with ios.open("rb") as f:
    plist = plistlib.load(f)
if plist.get("CFBundleDisplayName") != "픽도리":
    raise SystemExit("iOS launcher name was not configured.")
if plist.get("CFBundleName") != "Picdori":
    raise SystemExit("iOS bundle name was not configured.")
for key in ("NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"):
    if not plist.get(key):
        raise SystemExit(f"Missing iOS photo permission description: {key}")
for key in ("UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace"):
    if plist.get(key) is not True:
        raise SystemExit(f"Missing iOS Files visibility: {key}")

legacy_permission = [
    element for element in ET.parse(android).getroot().findall("uses-permission")
    if element.get("{http://schemas.android.com/apk/res/android}name")
       == "android.permission.WRITE_EXTERNAL_STORAGE"
]
if len(legacy_permission) != 1 or legacy_permission[0].get(
        "{http://schemas.android.com/apk/res/android}maxSdkVersion") != "29":
    raise SystemExit("Android legacy gallery permission must be limited to API 29.")
if legacy_permission[0].get(
        "{http://schemas.android.com/tools}replace") != "android:maxSdkVersion":
    raise SystemExit("Android legacy permission must override file_saver's maxSdkVersion.")

gradle = root / "android/app/build.gradle.kts"
if not gradle.exists():
    gradle = root / "android/app/build.gradle"
if "com.dudozi.picdori" not in gradle.read_text(encoding="utf-8"):
    raise SystemExit("Android application ID mismatch.")
if "com.dudozi.picdori" not in project.read_text(encoding="utf-8"):
    raise SystemExit("iOS bundle ID mismatch.")
if "name: picdori\n" not in (root / "pubspec.yaml").read_text(encoding="utf-8"):
    raise SystemExit("Flutter package name mismatch.")

print("Picdori app identity verified on Android and iOS.")

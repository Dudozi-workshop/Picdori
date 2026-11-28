#!/usr/bin/env python3
"""Set a distinct application ID for a side-by-side Android QA install.

Only applicationId and the launcher label change. Dart and Kotlin source,
the Android namespace, gallery permissions and platform channels stay intact.
Run after flutter create and configure_android.py, on the QA branch only.
"""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "android/app"
BASE_ID = "com.dudozi.picdori"
QA_ID = f"{BASE_ID}.qa"
QA_LABEL = "픽도리 QA"
ANDROID = "{http://schemas.android.com/apk/res/android}"

gradle = APP / "build.gradle.kts"
if not gradle.exists():
    gradle = APP / "build.gradle"
build = gradle.read_text(encoding="utf-8")
identity = r'(?m)^(\s*applicationId\s*(?:=\s*)?["\'])' + re.escape(BASE_ID) + r'(?:\.qa)?(["\'])'
build, count = re.subn(identity, lambda m: m[1] + QA_ID + m[2], build)
if count != 1:
    raise SystemExit(f"Expected one Android applicationId, got {count}.")
if not re.search(
    r'(?m)^\s*namespace\s*(?:=\s*)?["\']' + re.escape(BASE_ID) + r'["\']', build
):
    raise SystemExit("Android namespace must match the production Kotlin package.")

manifest_file = APP / "src/main/AndroidManifest.xml"
manifest = manifest_file.read_text(encoding="utf-8")
manifest, count = re.subn(
    r'(<application\b[^>]*\bandroid:label=")픽도리(?: QA)?(")',
    lambda m: m[1] + QA_LABEL + m[2],
    manifest,
    flags=re.DOTALL,
)
if count != 1:
    raise SystemExit("Expected one Android launcher label.")
# Android resolves unqualified class names against namespace at build time.
# Use the actual Kotlin name explicitly, independent of the final app ID.
manifest = manifest.replace('android:name=".MainActivity"',
                            f'android:name="{BASE_ID}.MainActivity"')
root = ET.fromstring(manifest)
application = root.find("application")
if application is None or application.get(f"{ANDROID}label") != QA_LABEL:
    raise SystemExit("QA application label was not configured.")
if not any(e.get(f"{ANDROID}name") == f"{BASE_ID}.MainActivity"
           for e in application.findall("activity")):
    raise SystemExit("QA launcher must use the existing native MainActivity.")
permissions = {e.get(f"{ANDROID}name"): e.get(f"{ANDROID}maxSdkVersion")
               for e in root.findall("uses-permission")}
if permissions.get("android.permission.WRITE_EXTERNAL_STORAGE") != "29":
    raise SystemExit("QA build must preserve the legacy gallery permission.")
for provider in application.findall("provider"):
    name = provider.get(f"{ANDROID}authorities", "")
    if name.startswith(BASE_ID) and not name.startswith(QA_ID + "."):
        raise SystemExit("A provider authority would collide with the base app.")

gradle.write_text(build, encoding="utf-8")
manifest_file.write_text(manifest, encoding="utf-8")
print(f"QA build uses {QA_ID} and preserves the native namespace {BASE_ID}.")

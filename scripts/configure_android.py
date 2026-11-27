#!/usr/bin/env python3
"""Configure Android app label and legacy gallery-write permission.

Modern Android uses scoped MediaStore for new gallery entries. Gal still
requires WRITE_EXTERNAL_STORAGE on Android 10/API 29 and below; never request
it on newer versions. Safe to run again after flutter create.
"""
from pathlib import Path
import re

manifest = Path(__file__).resolve().parents[1] / "android/app/src/main/AndroidManifest.xml"
if not manifest.exists():
    raise SystemExit("Missing Android manifest. Run flutter create first.")

source = manifest.read_text(encoding="utf-8")
updated, count = re.subn(
    r'(<application\b[^>]*\bandroid:label=")[^"]*(")',
    lambda m: m.group(1) + "픽도리" + m.group(2),
    source,
    count=1,
    flags=re.DOTALL,
)
if count != 1:
    raise SystemExit("Could not find the Android application label.")

# file_saver declares this permission with maxSdkVersion=28 while gal
# needs it on API 29. Override the attribute at app level, not the whole
# permission, so Android manifest merging remains deterministic.
tools_ns = 'xmlns:tools="http://schemas.android.com/tools"'
opening = re.search(r'<manifest\b[^>]*>', updated, flags=re.DOTALL)
if opening is None:
    raise SystemExit("Could not find the Android manifest element.")
if tools_ns not in opening.group():
    updated = (
        updated[:opening.end() - 1] + ' ' + tools_ns + '>' +
        updated[opening.end():]
    )

permission_name = "android.permission.WRITE_EXTERNAL_STORAGE"
permission = (
    '    <uses-permission android:name="' + permission_name + '" '
    'android:maxSdkVersion="29" '
    'tools:replace="android:maxSdkVersion" />\n'
)
matches = re.findall(
    r'<uses-permission\b[^>]*\bandroid:name="' +
    re.escape(permission_name) + r'"[^>]*/>',
    updated,
)
if len(matches) > 1:
    raise SystemExit("Duplicate WRITE_EXTERNAL_STORAGE permissions.")
if matches:
    # Replace a previously generated declaration with the bounded one.
    updated = updated.replace(matches[0], permission.strip())
else:
    application = re.search(r'^\s*<application\b', updated, flags=re.MULTILINE)
    if application is None:
        raise SystemExit("Android application element was not found.")
    updated = updated[:application.start()] + "\n" + permission + updated[application.start():]

manifest.write_text(updated, encoding="utf-8")
print(f"Android app label and API <= 29 gallery permission configured ({manifest})")

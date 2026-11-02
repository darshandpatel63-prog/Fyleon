#!/usr/bin/env python3
"""Patches the generated android/ project for Fyleon. Safe to run many times.

- app label, permissions, AdMob application id (from config/fyleon_config.json)
- minSdk >= 24
- verifies applicationId == com.fyleon.app
No secrets are read or written here.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"
TEST_APP_ID = "ca-app-pub-3940256099942544~3347511713"
WANTED_ID = "com.fyleon.app"
APP_LABEL = "Fyleon"


def fail(msg):
    print("PATCH ERROR:", msg)
    sys.exit(1)


def load_config():
    try:
        return json.loads((ROOT / "config/fyleon_config.json").read_text("utf-8"))
    except Exception as e:  # noqa
        print("config not readable, using defaults:", e)
        return {}


def set_permission(text, name, present, attrs=""):
    full = f"android.permission.{name}" if "." not in name else name
    pattern = re.compile(r'[ \t]*<uses-permission\b[^>]*android:name="' + re.escape(full) + r'"[^>]*/>[ \t]*\n?')
    text = pattern.sub("", text)
    if present:
        line = f'\n    <uses-permission android:name="{full}"{(" " + attrs) if attrs else ""}/>'
        text = re.sub(r"(<manifest\b[^>]*>)", lambda m: m.group(1) + line, text, count=1)
    return text


def patch_manifest(cfg):
    if not MANIFEST.exists():
        fail(f"{MANIFEST} not found. Run 'flutter create --platforms=android .' first.")
    text = MANIFEST.read_text("utf-8")

    admob = cfg.get("admob") or {}
    use_test = admob.get("useTestAds", True) is not False
    app_id = ((admob.get("android") or {}).get("appId") or "").strip()
    if use_test or not app_id:
        app_id = TEST_APP_ID
    all_files = bool((cfg.get("features") or {}).get("allFilesAccess", False))

    text = set_permission(text, "INTERNET", True)
    text = set_permission(text, "ACCESS_NETWORK_STATE", True)
    text = set_permission(text, "com.google.android.gms.permission.AD_ID", True)
    text = set_permission(text, "MANAGE_EXTERNAL_STORAGE", all_files)
    text = set_permission(text, "READ_EXTERNAL_STORAGE", all_files, 'android:maxSdkVersion="32"')

    # app label
    text = re.sub(r'(<application\b[^>]*?android:label=")[^"]*(")', r"\g<1>" + APP_LABEL + r"\2", text, count=1)

    # AdMob application id
    meta = (
        '\n        <meta-data'
        '\n            android:name="com.google.android.gms.ads.APPLICATION_ID"'
        f'\n            android:value="{app_id}"/>'
    )
    if "com.google.android.gms.ads.APPLICATION_ID" in text:
        text = re.sub(
            r'(com\.google\.android\.gms\.ads\.APPLICATION_ID"\s*android:value=")[^"]*(")',
            r"\g<1>" + app_id + r"\2",
            text,
            count=1,
        )
    else:
        text = re.sub(r"(<application\b[^>]*>)", lambda m: m.group(1) + meta, text, count=1)

    MANIFEST.write_text(text, "utf-8")
    print(f"manifest ok (test ads: {use_test or app_id == TEST_APP_ID}, allFilesAccess: {all_files})")


def patch_gradle():
    gradle = None
    for name in ("build.gradle.kts", "build.gradle"):
        f = ROOT / "android/app" / name
        if f.exists():
            gradle = f
            break
    if gradle is None:
        fail("android/app/build.gradle(.kts) not found")
    text = gradle.read_text("utf-8")

    m = re.search(r'applicationId\s*=?\s*"([^"]+)"', text)
    if not m or m.group(1) != WANTED_ID:
        fail(f"applicationId is {m.group(1) if m else 'missing'}, expected {WANTED_ID}")

    def bump(match):
        value = match.group(3)
        if value.isdigit() and int(value) >= 24:
            return match.group(0)
        if value == "flutter.minSdkVersion":
            return match.group(0)
        return f"{match.group(1)}{match.group(2)}24"

    text = re.sub(r"(minSdk(?:Version)?)(\s*=\s*|\s+)(flutter\.minSdkVersion|\d+)", bump, text)
    gradle.write_text(text, "utf-8")
    print("gradle ok:", gradle.name, "applicationId", WANTED_ID)


if __name__ == "__main__":
    patch_manifest(load_config())
    patch_gradle()

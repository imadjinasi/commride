#!/usr/bin/env python3
"""Verify generated CommRide Android/iOS declarations without real secrets."""

from __future__ import annotations

import plistlib
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = "http://schemas.android.com/apk/res/android"


def android_attr(name: str) -> str:
    return f"{{{ANDROID_NS}}}{name}"


def verify_android() -> None:
    manifest_path = ROOT / "android/app/src/main/AndroidManifest.xml"
    tree = ET.parse(manifest_path)
    manifest = tree.getroot()

    permissions = {
        node.get(android_attr("name"))
        for node in manifest.findall("uses-permission")
    }
    required = {
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_LOCATION",
        "android.permission.POST_NOTIFICATIONS",
    }
    missing = required - permissions
    if missing:
        raise SystemExit(f"Missing Android permissions: {sorted(missing)}")

    if "android.permission.ACCESS_BACKGROUND_LOCATION" in permissions:
        raise SystemExit(
            "ACCESS_BACKGROUND_LOCATION is not part of the accepted MVP policy."
        )

    application = manifest.find("application")
    if application is None:
        raise SystemExit("Android application element missing.")

    maps_metadata = [
        node
        for node in application.findall("meta-data")
        if node.get(android_attr("name")) == "com.google.android.geo.API_KEY"
    ]
    if len(maps_metadata) != 1:
        raise SystemExit("Google Maps Android metadata is missing or duplicated.")

    if maps_metadata[0].get(android_attr("value")) != "@string/google_maps_key":
        raise SystemExit("Google Maps Android key must come from a resource hook.")

    gradle = ROOT / "android/app/build.gradle.kts"
    legacy_gradle = ROOT / "android/app/build.gradle"
    gradle_path = gradle if gradle.exists() else legacy_gradle
    content = gradle_path.read_text(encoding="utf-8")
    if "minSdk = 24" not in content and "minSdkVersion 24" not in content:
        raise SystemExit("Android minSdk 24 declaration missing.")


def verify_ios() -> None:
    plist_path = ROOT / "ios/Runner/Info.plist"
    with plist_path.open("rb") as handle:
        plist = plistlib.load(handle)

    if not plist.get("NSLocationWhenInUseUsageDescription"):
        raise SystemExit("iOS When In Use location explanation missing.")
    if not plist.get("NSLocationAlwaysAndWhenInUseUsageDescription"):
        raise SystemExit("iOS background location explanation missing.")

    modes = set(plist.get("UIBackgroundModes", []))
    required_modes = {"location", "remote-notification"}
    missing_modes = required_modes - modes
    if missing_modes:
        raise SystemExit(
            f"Missing iOS background modes: {sorted(missing_modes)}"
        )

    if "COMMRIDE_MAPS_API_KEY" not in plist:
        raise SystemExit("iOS Maps key hook missing.")

    app_delegate = (
        ROOT / "ios/Runner/AppDelegate.swift"
    ).read_text(encoding="utf-8")
    if "GMSServices.provideAPIKey" not in app_delegate:
        raise SystemExit("iOS Google Maps setup missing.")
    if "configureNotificationCenterDelegate()" not in app_delegate:
        raise SystemExit("FlutterFire notification delegate setup missing.")


def verify_no_checked_in_provider_secrets() -> None:
    forbidden = (
        ROOT / "android/app/google-services.json",
        ROOT / "ios/Runner/GoogleService-Info.plist",
        ROOT / "android/key.properties",
        ROOT / "android/app/upload-keystore.jks",
    )
    for path in forbidden:
        if path.exists():
            # Generated local files may exist during real-device work. This
            # verifier is used by CI after clean checkout, so finding one here
            # means the repository bootstrap unexpectedly carries a secret-ish
            # provider/signing file.
            raise SystemExit(f"Provider/signing file must not be in CI source: {path}")


def main() -> None:
    verify_no_checked_in_provider_secrets()
    verify_android()
    verify_ios()
    print("commride-platform-verification-ok")


if __name__ == "__main__":
    main()

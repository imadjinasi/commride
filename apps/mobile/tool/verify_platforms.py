#!/usr/bin/env python3
"""Verify generated Android/iOS declarations without real provider secrets."""
from __future__ import annotations

import plistlib
import re
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = "http://schemas.android.com/apk/res/android"


def android_attr(name: str) -> str:
    return f"{{{ANDROID_NS}}}{name}"


def verify_android() -> None:
    tree = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml")
    manifest = tree.getroot()
    permissions = {
        node.get(android_attr("name"))
        for node in manifest.findall("uses-permission")
    }
    required = {
        "android.permission.INTERNET",
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_LOCATION",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.RECORD_AUDIO",
        "android.permission.FOREGROUND_SERVICE_MICROPHONE",
        "android.permission.BLUETOOTH_CONNECT",
    }
    if required - permissions:
        raise SystemExit(f"Missing Android permissions: {sorted(required - permissions)}")
    if "android.permission.ACCESS_BACKGROUND_LOCATION" in permissions:
        raise SystemExit("ACCESS_BACKGROUND_LOCATION is not part of the accepted MVP policy.")
    application = manifest.find("application")
    if application is None:
        raise SystemExit("Android application element missing.")
    main_activity = next(
        (
            node
            for node in application.findall("activity")
            if node.get(android_attr("name")) == ".MainActivity"
        ),
        None,
    )
    if main_activity is None:
        raise SystemExit("Android MainActivity element missing.")
    if main_activity.get(android_attr("screenOrientation")) != "user":
        raise SystemExit(
            "Android MainActivity must respect the user's device orientation preference."
        )
    maps_metadata = [
        node for node in application.findall("meta-data")
        if node.get(android_attr("name")) == "com.google.android.geo.API_KEY"
    ]
    if maps_metadata:
        raise SystemExit("Obsolete Google Maps API-key metadata remains.")
    if (ROOT / "android/app/src/main/res/values/commride_maps.xml").exists():
        raise SystemExit("Obsolete Google Maps key resource remains.")
    gradle = ROOT / "android/app/build.gradle.kts"
    if not gradle.exists():
        gradle = ROOT / "android/app/build.gradle"
    content = gradle.read_text(encoding="utf-8")
    if "minSdk = 24" not in content and "minSdkVersion 24" not in content:
        raise SystemExit("Android minSdk 24 declaration missing.")
    if "MAPS_API_KEY" in content or "commRideMapsApiKey" in content:
        raise SystemExit("Obsolete Google Navigation Gradle wiring remains.")
    activities = list((ROOT / "android/app/src/main/kotlin").rglob("MainActivity.kt"))
    if len(activities) != 1 or "commride/media_keys" not in activities[0].read_text(
        encoding="utf-8"
    ):
        raise SystemExit("Android media-key channel missing.")
    service = activities[0].with_name("IntercomService.kt")
    if (
        "IntercomService.register(this" not in activities[0].read_text(encoding="utf-8")
        or not service.exists()
        or '"commride/intercom_service"' not in service.read_text(encoding="utf-8")
    ):
        raise SystemExit("Android intercom service channel missing.")
    services = {
        node.get(android_attr("name")): node.get(android_attr("foregroundServiceType"))
        for node in application.findall("service")
    }
    if services.get(".IntercomService") != "microphone":
        raise SystemExit("Intercom microphone foreground service missing.")
    tools_node = "{http://schemas.android.com/tools}node"
    removed = {
        node.get(android_attr("name"))
        for node in manifest.findall("uses-permission")
        if node.get(tools_node) == "remove"
    }
    if "android.permission.CAMERA" not in removed:
        raise SystemExit("Intercom must not request the camera permission.")
    if gradle.name == "build.gradle.kts" and (
        "commRideKeystoreProperties" not in content
        or 'signingConfigs.getByName("release")' not in content
    ):
        raise SystemExit("Android release signing wiring missing.")
    app_id = re.findall(r'applicationId\s*=?\s*[\"\']([^\"\']+)[\"\']', content)
    if app_id != ["io.github.imadjinasi.commride"]:
        raise SystemExit("Android application ID does not match the accepted Firebase registration.")


def verify_ios() -> None:
    with (ROOT / "ios/Runner/Info.plist").open("rb") as handle:
        plist = plistlib.load(handle)
    for name in ("NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"):
        if not plist.get(name):
            raise SystemExit("iOS location explanation missing.")
    missing = {"location", "remote-notification"} - set(plist.get("UIBackgroundModes", []))
    if missing:
        raise SystemExit(f"Missing iOS background modes: {sorted(missing)}")
    if "COMMRIDE_MAPS_API_KEY" in plist:
        raise SystemExit("Obsolete iOS Google Maps key remains.")
    delegate = (ROOT / "ios/Runner/AppDelegate.swift").read_text(encoding="utf-8")
    if "GoogleMaps" in delegate or "GMSServices" in delegate:
        raise SystemExit("Obsolete iOS Google Maps setup remains.")
    if "configureNotificationCenterDelegate()" not in delegate:
        raise SystemExit("FlutterFire notification delegate setup missing.")


def verify_no_checked_in_provider_secrets() -> None:
    # Run this clean-source verifier before local provider/signing setup.
    for relative in (
        "android/app/google-services.json",
        "ios/Runner/GoogleService-Info.plist",
        "android/key.properties",
        "android/app/upload-keystore.jks",
    ):
        if (ROOT / relative).exists():
            raise SystemExit(f"Provider/signing file must not be in CI source: {relative}")


def main() -> None:
    verify_no_checked_in_provider_secrets()
    verify_android()
    verify_ios()
    print("commride-platform-verification-ok")


if __name__ == "__main__":
    main()

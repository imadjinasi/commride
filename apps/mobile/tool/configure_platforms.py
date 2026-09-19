#!/usr/bin/env python3
"""Apply CommRide's reproducible Android/iOS platform declarations.

Run after:
  flutter create --platforms=android,ios --project-name commride_mobile \
    --org "${COMMRIDE_ORG:-io.github.imadjinasi}" .

Map keys are read from the environment and written only into generated native
files. They must never be committed.
"""

from __future__ import annotations

import os
import plistlib
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID_NS)


def android_attr(name: str) -> str:
    return f"{{{ANDROID_NS}}}{name}"


def configure_android() -> None:
    manifest_path = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not manifest_path.exists():
        raise SystemExit("Android project missing. Run flutter create first.")

    tree = ET.parse(manifest_path)
    manifest = tree.getroot()

    required_permissions = (
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_LOCATION",
        "android.permission.POST_NOTIFICATIONS",
    )
    existing = {
        node.get(android_attr("name"))
        for node in manifest.findall("uses-permission")
    }
    insert_at = 0
    for permission in required_permissions:
        if permission in existing:
            continue
        node = ET.Element("uses-permission")
        node.set(android_attr("name"), permission)
        manifest.insert(insert_at, node)
        insert_at += 1

    application = manifest.find("application")
    if application is None:
        raise SystemExit("Android application element missing.")

    metadata = None
    for node in application.findall("meta-data"):
        if node.get(android_attr("name")) == "com.google.android.geo.API_KEY":
            metadata = node
            break
    if metadata is None:
        metadata = ET.Element("meta-data")
        metadata.set(android_attr("name"), "com.google.android.geo.API_KEY")
        application.append(metadata)
    metadata.set(android_attr("value"), "@string/google_maps_key")

    tree.write(manifest_path, encoding="utf-8", xml_declaration=True)

    values_dir = ROOT / "android/app/src/main/res/values"
    values_dir.mkdir(parents=True, exist_ok=True)
    maps_key = os.environ.get("COMMRIDE_MAPS_ANDROID_API_KEY", "")
    escaped_key = (
        maps_key.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )
    (values_dir / "commride_maps.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <string name="google_maps_key" translatable="false">{escaped_key}</string>\n'
        "</resources>\n",
        encoding="utf-8",
    )

    for gradle_name in ("build.gradle.kts", "build.gradle"):
        gradle_path = ROOT / "android/app" / gradle_name
        if not gradle_path.exists():
            continue
        content = gradle_path.read_text(encoding="utf-8")
        content = content.replace(
            "minSdk = flutter.minSdkVersion",
            "minSdk = 24",
        )
        content = content.replace(
            "minSdkVersion flutter.minSdkVersion",
            "minSdkVersion 24",
        )
        gradle_path.write_text(content, encoding="utf-8")


def configure_ios() -> None:
    plist_path = ROOT / "ios/Runner/Info.plist"
    if not plist_path.exists():
        raise SystemExit("iOS project missing. Run flutter create first.")

    with plist_path.open("rb") as handle:
        plist = plistlib.load(handle)

    plist["NSLocationWhenInUseUsageDescription"] = (
        "CommRide menggunakan lokasi Anda hanya saat Ride aktif untuk "
        "membantu rombongan tetap terkoordinasi."
    )
    # Geolocator's iOS background implementation expects this key to be
    # declared. CommRide still requests When In Use first and does not
    # programmatically request Always in the MVP.
    plist["NSLocationAlwaysAndWhenInUseUsageDescription"] = (
        "CommRide dapat melanjutkan sesi lokasi Ride yang Anda mulai secara "
        "eksplisit ketika layar terkunci atau aplikasi berada di latar."
    )
    background_modes = list(plist.get("UIBackgroundModes", []))
    if "location" not in background_modes:
        background_modes.append("location")
    plist["UIBackgroundModes"] = background_modes
    plist["COMMRIDE_MAPS_API_KEY"] = os.environ.get(
        "COMMRIDE_MAPS_IOS_API_KEY", ""
    )

    with plist_path.open("wb") as handle:
        plistlib.dump(plist, handle, sort_keys=False)

    app_delegate = ROOT / "ios/Runner/AppDelegate.swift"
    if not app_delegate.exists():
        raise SystemExit("iOS AppDelegate.swift missing.")

    content = app_delegate.read_text(encoding="utf-8")
    if "import GoogleMaps" not in content:
        content = content.replace(
            "import Flutter\n",
            "import Flutter\nimport GoogleMaps\n",
            1,
        )

    marker = "    GeneratedPluginRegistrant.register(with: self)"
    setup = """    if let mapsKey = Bundle.main.object(
      forInfoDictionaryKey: "COMMRIDE_MAPS_API_KEY"
    ) as? String, !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    }
"""
    if "GMSServices.provideAPIKey" not in content:
        if marker not in content:
            raise SystemExit("Unexpected iOS AppDelegate template.")
        content = content.replace(marker, setup + marker, 1)
    app_delegate.write_text(content, encoding="utf-8")


def main() -> None:
    configure_android()
    configure_ios()
    print("CommRide platform declarations configured.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Apply reproducible CommRide declarations to generated Android/iOS projects.

Active Ride navigation is MapLibre-based and has no client-side Google Maps
credential. Firebase provider files and signing credentials remain local and
untracked.
"""
from __future__ import annotations

import plistlib
import re
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = "http://schemas.android.com/apk/res/android"
ANDROID_APPLICATION_ID = "io.github.imadjinasi.commride"
ET.register_namespace("android", ANDROID_NS)


def android_attr(name: str) -> str:
    return f"{{{ANDROID_NS}}}{name}"


RELEASE_SIGNING_MARKER = "commRideKeystoreProperties"

RELEASE_SIGNING_HEADER = """// Release signing reads android/key.properties, which stays local and
// untracked. Without it, release builds fall back to the debug key so CI can
// still build; such a build must never be uploaded to Google Play.
val commRideKeystoreProperties = java.util.Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

"""

RELEASE_SIGNING_CONFIG = """    signingConfigs {
        create("release") {
            if (!commRideKeystoreProperties.isEmpty()) {
                keyAlias = commRideKeystoreProperties.getProperty("keyAlias")
                keyPassword = commRideKeystoreProperties.getProperty("keyPassword")
                storeFile = file(commRideKeystoreProperties.getProperty("storeFile"))
                storePassword = commRideKeystoreProperties.getProperty("storePassword")
            }
        }
    }

"""

RELEASE_SIGNING_SELECTION = """signingConfig = if (commRideKeystoreProperties.isEmpty()) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }"""


def configure_release_signing(content: str) -> str:
    """Wire the Play upload key into Kotlin Gradle release builds."""
    if RELEASE_SIGNING_MARKER in content:
        return content
    if (
        "\nandroid {" not in "\n" + content
        or "    buildTypes {" not in content
        or 'signingConfig = signingConfigs.getByName("debug")' not in content
    ):
        raise SystemExit(
            "Unexpected Android release build template; "
            "refusing unsafe signing patch."
        )
    content = content.replace("android {", RELEASE_SIGNING_HEADER + "android {", 1)
    content = content.replace(
        "    buildTypes {", RELEASE_SIGNING_CONFIG + "    buildTypes {", 1
    )
    return content.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        RELEASE_SIGNING_SELECTION,
        1,
    )


def configure_android() -> None:
    manifest_path = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not manifest_path.exists():
        raise SystemExit("Android project missing. Run flutter create first.")

    tree = ET.parse(manifest_path)
    manifest = tree.getroot()
    required_permissions = (
        "android.permission.INTERNET",
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
    for permission in required_permissions:
        if permission not in existing:
            node = ET.Element("uses-permission")
            node.set(android_attr("name"), permission)
            manifest.insert(0, node)

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
    # Respect the Rider's Android rotation preference. "user" follows the
    # device-level orientation choice instead of forcing sensor rotation.
    main_activity.set(android_attr("screenOrientation"), "user")

    for node in list(application.findall("meta-data")):
        if node.get(android_attr("name")) == "com.google.android.geo.API_KEY":
            application.remove(node)

    tree.write(manifest_path, encoding="utf-8", xml_declaration=True)
    obsolete = ROOT / "android/app/src/main/res/values/commride_maps.xml"
    obsolete.unlink(missing_ok=True)

    configured = False
    for gradle_name in ("build.gradle.kts", "build.gradle"):
        path = ROOT / "android/app" / gradle_name
        if not path.exists():
            continue
        content = path.read_text(encoding="utf-8")
        content = content.replace(
            "minSdk = flutter.minSdkVersion",
            "minSdk = 24",
        )
        content = content.replace(
            "minSdkVersion flutter.minSdkVersion",
            "minSdkVersion 24",
        )
        content = content.replace(
            "JavaVersion.VERSION_11",
            "JavaVersion.VERSION_17",
        )

        # Remove Google Navigation wiring previously generated by the pilot.
        content = content.replace("import java.util.Properties\n\n", "")
        content = re.sub(
            r"val commRideLocalProperties = Properties\(\)\.apply \{.*?"
            r"\?: \"UNCONFIGURED\"\n\n",
            "",
            content,
            flags=re.DOTALL,
        )
        content = re.sub(
            r"^\s*manifestPlaceholders\[\"MAPS_API_KEY\"\]"
            r"\s*=\s*commRideMapsApiKey\s*$\n?",
            "",
            content,
            flags=re.MULTILINE,
        )
        content = re.sub(
            r"^\s*isCoreLibraryDesugaringEnabled\s*=\s*true\s*$\n?",
            "",
            content,
            flags=re.MULTILINE,
        )
        content = content.replace(
            '\n\ndependencies {\n'
            '    coreLibraryDesugaring('
            '"com.android.tools:desugar_jdk_libs_nio:2.1.5")\n'
            '}\n',
            "\n",
        )

        content, count = re.subn(
            r"""(applicationId\s*=?\s*)["'][^"']+["']""",
            lambda match: match[1] + '"' + ANDROID_APPLICATION_ID + '"',
            content,
        )
        if count != 1:
            raise SystemExit(
                "Unexpected Android applicationId template; "
                "refusing unsafe patch."
            )

        if gradle_name == "build.gradle.kts":
            content = configure_release_signing(content)

        path.write_text(content, encoding="utf-8")
        configured = True

    if not configured:
        raise SystemExit("Android app Gradle file missing.")


def configure_ios() -> None:
    path = ROOT / "ios/Runner/Info.plist"
    if not path.exists():
        raise SystemExit("iOS project missing. Run flutter create first.")

    with path.open("rb") as handle:
        plist = plistlib.load(handle)
    plist["NSLocationWhenInUseUsageDescription"] = (
        "CommRide menggunakan lokasi Anda hanya saat Ride aktif untuk "
        "membantu rombongan tetap terkoordinasi."
    )
    plist["NSLocationAlwaysAndWhenInUseUsageDescription"] = (
        "CommRide dapat melanjutkan sesi lokasi Ride yang Anda mulai secara "
        "eksplisit ketika layar terkunci atau aplikasi berada di latar."
    )
    modes = list(plist.get("UIBackgroundModes", []))
    for mode in ("location", "remote-notification"):
        if mode not in modes:
            modes.append(mode)
    plist["UIBackgroundModes"] = modes
    plist.pop("COMMRIDE_MAPS_API_KEY", None)
    with path.open("wb") as handle:
        plistlib.dump(plist, handle, sort_keys=False)

    delegate = ROOT / "ios/Runner/AppDelegate.swift"
    if not delegate.exists():
        raise SystemExit("iOS AppDelegate.swift missing.")
    content = delegate.read_text(encoding="utf-8")
    content = content.replace("import GoogleMaps\n", "")
    content = re.sub(
        r'    if let mapsKey = Bundle\.main\.object\(\s*'
        r'forInfoDictionaryKey: "COMMRIDE_MAPS_API_KEY"\s*'
        r'\) as\? String, !mapsKey\.isEmpty \{\s*'
        r'GMSServices\.provideAPIKey\(mapsKey\)\s*\}\n',
        "",
        content,
    )

    setup = (
        "    FLTFirebaseMessagingPlugin."
        "configureNotificationCenterDelegate()\n"
    )
    if "configureNotificationCenterDelegate()" not in content:
        marker = (
            "    return super.application(application, "
            "didFinishLaunchingWithOptions: launchOptions)"
        )
        if marker not in content:
            raise SystemExit(
                "Unexpected iOS delegate template; refusing unsafe patch."
            )
        content = content.replace(marker, setup + marker, 1)

    delegate.write_text(content, encoding="utf-8")


def main() -> None:
    configure_android()
    configure_ios()
    print("CommRide platform declarations configured.")


if __name__ == "__main__":
    main()

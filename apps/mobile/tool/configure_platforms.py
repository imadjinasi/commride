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
TOOLS_NS = "http://schemas.android.com/tools"
ANDROID_APPLICATION_ID = "io.github.imadjinasi.commride"
ET.register_namespace("android", ANDROID_NS)
ET.register_namespace("tools", TOOLS_NS)


def android_attr(name: str) -> str:
    return f"{{{ANDROID_NS}}}{name}"


def tools_attr(name: str) -> str:
    return f"{{{TOOLS_NS}}}{name}"


# Ride voice intercom: Cloudflare RealtimeKit through CommRide's own bridge
# (tool/android/CommRideIntercom.kt). See docs/voice-intercom-decision-2026-10-16.md.
INTERCOM_SOURCE = Path(__file__).resolve().parent / "android/CommRideIntercom.kt"
INTERCOM_DEPENDENCY = "com.cloudflare.realtimekit:core:3.2.0"
# RealtimeKit's AAR metadata requires compileSdk 37 and core library
# desugaring. compileSdk only selects the API stubs compiled against; it does
# not change targetSdk or minSdk.
INTERCOM_COMPILE_SDK = "37"
INTERCOM_DESUGAR_DEPENDENCY = "com.android.tools:desugar_jdk_libs:2.1.5"
INTERCOM_PERMISSIONS = (
    "android.permission.RECORD_AUDIO",
    "android.permission.MODIFY_AUDIO_SETTINGS",
    "android.permission.FOREGROUND_SERVICE_MICROPHONE",
    "android.permission.BLUETOOTH_CONNECT",
)
# The SDK also declares camera, storage and screen sharing; CommRide voice
# uses none of them, so the merged manifest drops them.
INTERCOM_REMOVED_PERMISSIONS = (
    "android.permission.CAMERA",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
)
INTERCOM_REMOVED_COMPONENTS = (
    ("service", "com.cloudflare.realtimekit.media.ScreenCaptureService"),
    ("activity", "com.cloudflare.realtimekit.media.ScreenCaptureActivity"),
)


RELEASE_SIGNING_MARKER = "commRideKeystoreProperties"

# Gradle's Kotlin DSL shadows the `java` package with the Java extension, so
# the class is imported under an alias instead of written fully qualified.
RELEASE_SIGNING_IMPORT = "import java.util.Properties as CommRideProperties\n"

RELEASE_SIGNING_HEADER = """// Release signing reads android/key.properties, which stays local and
// untracked. Without it, release builds fall back to the debug key so CI can
// still build; such a build must never be uploaded to Google Play.
val commRideKeystoreProperties = CommRideProperties().apply {
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


MEDIA_KEYS_CHANNEL = "commride/media_keys"

MEDIA_KEYS_ACTIVITY = """
import android.media.AudioManager
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Media keys let Riders control whatever music app is playing without the
// notification-access permission that reading track details would need.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CommRideIntercom(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "commride/media_keys")
            .setMethodCallHandler { call, result ->
                val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                if (call.method == "isMusicActive") {
                    // Whether any app is playing audio; needs no permission.
                    result.success(audio.isMusicActive)
                    return@setMethodCallHandler
                }
                val code = when (call.arguments as? String) {
                    "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                    "playPause" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                    "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                    else -> null
                }
                if (call.method != "send" || code == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
                audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
                result.success(null)
            }
    }
}
"""


def configure_media_keys() -> None:
    """Install the media-key channel in the generated Android MainActivity."""
    activities = sorted(
        (ROOT / "android/app/src/main/kotlin").rglob("MainActivity.kt")
    )
    if len(activities) != 1:
        raise SystemExit("Expected exactly one Android MainActivity.kt.")
    path = activities[0]
    content = path.read_text(encoding="utf-8")
    package = next(
        (line for line in content.splitlines() if line.startswith("package ")),
        None,
    )
    if package is not None and content == package + "\n" + MEDIA_KEYS_ACTIVITY:
        return
    # Regenerate either the Flutter template or an earlier CommRide version.
    if package is None or (
        "class MainActivity : FlutterActivity()" not in content
        and MEDIA_KEYS_CHANNEL not in content
    ):
        raise SystemExit(
            "Unexpected Android MainActivity template; refusing unsafe patch."
        )
    path.write_text(package + "\n" + MEDIA_KEYS_ACTIVITY, encoding="utf-8")


def configure_intercom_source() -> None:
    """Place the intercom bridge next to MainActivity in the app package."""
    activity = next((ROOT / "android/app/src/main/kotlin").rglob("MainActivity.kt"))
    package = next(
        line
        for line in activity.read_text(encoding="utf-8").splitlines()
        if line.startswith("package ")
    )
    target = activity.with_name("CommRideIntercom.kt")
    target.write_text(
        package + "\n\n" + INTERCOM_SOURCE.read_text(encoding="utf-8"),
        encoding="utf-8",
    )


def configure_intercom_manifest(manifest: ET.Element) -> None:
    existing = {
        node.get(android_attr("name")): node
        for node in manifest.findall("uses-permission")
    }
    for permission in INTERCOM_PERMISSIONS:
        if permission not in existing:
            node = ET.Element("uses-permission")
            node.set(android_attr("name"), permission)
            manifest.insert(0, node)
    for permission in INTERCOM_REMOVED_PERMISSIONS:
        node = existing.get(permission)
        if node is None:
            node = ET.Element("uses-permission")
            node.set(android_attr("name"), permission)
            manifest.insert(0, node)
        node.set(tools_attr("node"), "remove")

    application = manifest.find("application")
    if application is None:
        raise SystemExit("Android application element missing.")
    for tag, name in INTERCOM_REMOVED_COMPONENTS:
        if not any(
            node.get(android_attr("name")) == name
            for node in application.findall(tag)
        ):
            node = ET.SubElement(application, tag)
            node.set(android_attr("name"), name)
            node.set(tools_attr("node"), "remove")
    if not any(
        node.get(android_attr("name")) == ".IntercomService"
        for node in application.findall("service")
    ):
        service = ET.SubElement(application, "service")
        service.set(android_attr("name"), ".IntercomService")
        service.set(android_attr("exported"), "false")
        service.set(android_attr("foregroundServiceType"), "microphone")


def configure_intercom_gradle(content: str, kotlin_dsl: bool) -> str:
    if kotlin_dsl:
        content = re.sub(
            r"compileSdk = (flutter\.compileSdkVersion|\d+)",
            f"compileSdk = {INTERCOM_COMPILE_SDK}",
            content,
            count=1,
        )
        desugar_flag = "isCoreLibraryDesugaringEnabled = true"
        target = "targetCompatibility = JavaVersion.VERSION_17"
    else:
        content = re.sub(
            r"compileSdk(Version)? (flutter\.compileSdkVersion|\d+)",
            f"compileSdk {INTERCOM_COMPILE_SDK}",
            content,
            count=1,
        )
        desugar_flag = "coreLibraryDesugaringEnabled true"
        target = "targetCompatibility JavaVersion.VERSION_17"
    if desugar_flag not in content:
        match = re.search(rf"^(\s*){re.escape(target)}\s*$", content, re.MULTILINE)
        if match is None:
            raise SystemExit(
                "Unexpected Android compileOptions template; "
                "refusing unsafe desugaring patch."
            )
        content = (
            content[: match.end()]
            + "\n"
            + match.group(1)
            + desugar_flag
            + content[match.end():]
        )

    if INTERCOM_DEPENDENCY in content:
        return content
    if kotlin_dsl:
        lines = (
            f'    implementation("{INTERCOM_DEPENDENCY}")\n'
            f'    coreLibraryDesugaring("{INTERCOM_DESUGAR_DEPENDENCY}")\n'
        )
    else:
        lines = (
            f'    implementation "{INTERCOM_DEPENDENCY}"\n'
            f'    coreLibraryDesugaring "{INTERCOM_DESUGAR_DEPENDENCY}"\n'
        )
    return (
        content.rstrip("\n")
        + "\n\ndependencies {\n"
        + "    // Ride voice intercom (Cloudflare RealtimeKit, audio only).\n"
        + lines
        + "}\n"
    )


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
    content = RELEASE_SIGNING_IMPORT + content
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

    configure_intercom_manifest(manifest)

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
        content = configure_intercom_gradle(
            content, kotlin_dsl=gradle_name == "build.gradle.kts"
        )

        path.write_text(content, encoding="utf-8")
        configured = True

    if not configured:
        raise SystemExit("Android app Gradle file missing.")

    configure_media_keys()
    configure_intercom_source()


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

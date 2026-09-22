#!/usr/bin/env python3
"""Regression fixtures; actual Flutter-generated projects are verified in CI too."""
import plistlib
from pathlib import Path
import tempfile
import unittest

import configure_platforms as configure
import verify_platforms as verify


class PlatformTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.old_config_root, self.old_verify_root = configure.ROOT, verify.ROOT
        configure.ROOT = verify.ROOT = self.root
        self.write("android/app/src/main/AndroidManifest.xml", '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
<application>
<activity android:name=".MainActivity"/>
<meta-data android:name="com.google.android.geo.API_KEY" android:value="@string/google_maps_key"/>
</application>
</manifest>''')
        self.write("android/app/build.gradle.kts", '''android {
    namespace = "io.github.imadjinasi.commride_mobile"
    defaultConfig {
        applicationId = "io.github.imadjinasi.commride_mobile"
        minSdk = flutter.minSdkVersion
    }
}''')
        self.write("android/app/src/main/res/values/commride_maps.xml", "<resources/>")
        plist_path = self.root / "ios/Runner/Info.plist"
        plist_path.parent.mkdir(parents=True, exist_ok=True)
        plist_path.write_bytes(plistlib.dumps({"COMMRIDE_MAPS_API_KEY": "fixture-only"}))
        self.write("ios/Runner/AppDelegate.swift", '''import Flutter
import GoogleMaps
func application() {
    if let mapsKey = Bundle.main.object(
      forInfoDictionaryKey: "COMMRIDE_MAPS_API_KEY"
    ) as? String, !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
}
''')

    def tearDown(self):
        configure.ROOT, verify.ROOT = self.old_config_root, self.old_verify_root
        self.tmp.cleanup()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_repeatable_migration_preserves_location_and_messaging(self):
        configure.main()
        verify.main()
        before = {str(p.relative_to(self.root)): p.read_bytes()
                  for p in self.root.rglob("*") if p.is_file()}
        configure.main()
        verify.main()
        after = {str(p.relative_to(self.root)): p.read_bytes()
                 for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(before, after)
        delegate = (self.root / "ios/Runner/AppDelegate.swift").read_text()
        self.assertEqual(delegate.count("configureNotificationCenterDelegate()"), 1)
        self.assertNotIn("GoogleMaps", delegate)
        self.assertNotIn("GMSServices", delegate)
        manifest = (self.root / "android/app/src/main/AndroidManifest.xml").read_text()
        self.assertNotIn("com.google.android.geo.API_KEY", manifest)
        self.assertNotIn("MAPS_API_KEY", manifest)
        self.assertIn('android:screenOrientation="user"', manifest)
        gradle = (self.root / "android/app/build.gradle.kts").read_text()
        self.assertNotIn("MAPS_API_KEY", gradle)
        self.assertNotIn("commRideMapsApiKey", gradle)
        self.assertNotIn("coreLibraryDesugaring", gradle)

    def test_wrong_orientation_policy_is_rejected(self):
        configure.main()
        path = self.root / "android/app/src/main/AndroidManifest.xml"
        text = path.read_text().replace(
            'android:screenOrientation="user"',
            'android:screenOrientation="sensor"',
        )
        path.write_text(text)
        with self.assertRaises(SystemExit):
            verify.verify_android()

    def test_release_internet_permission_is_required(self):
        configure.main()
        path = self.root / "android/app/src/main/AndroidManifest.xml"
        text = path.read_text().replace('android:name="android.permission.INTERNET"', 'android:name="removed"')
        path.write_text(text)
        with self.assertRaises(SystemExit):
            verify.verify_android()

    def test_wrong_application_id_is_rejected(self):
        configure.main()
        path = self.root / "android/app/build.gradle.kts"
        path.write_text(path.read_text().replace('applicationId = "io.github.imadjinasi.commride"', 'applicationId = "wrong"'))
        with self.assertRaises(SystemExit):
            verify.verify_android()

    def test_missing_fcm_delegate_is_rejected(self):
        configure.main()
        path = self.root / "ios/Runner/AppDelegate.swift"
        path.write_text(path.read_text().replace("configureNotificationCenterDelegate()", "removed()"))
        with self.assertRaises(SystemExit):
            verify.verify_ios()


if __name__ == "__main__":
    unittest.main()

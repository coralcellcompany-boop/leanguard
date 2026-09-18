"""Checks the optional native Firebase copy phase without provider credentials."""
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


class FirebasePlistCopyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="leanguard-native-config-")
        self.root = Path(self.temp.name)
        self.source = self.root / "ios" / "Runner" / "GoogleService-Info.plist"
        self.source.parent.mkdir(parents=True)
        self.output = self.root / "build" / "Runner.app" / "GoogleService-Info.plist"
        self.output.parent.mkdir(parents=True)
        self.env = {
            **os.environ,
            "SRCROOT": str(self.root / "ios"),
            "TARGET_BUILD_DIR": str(self.root / "build"),
            "UNLOCALIZED_RESOURCES_FOLDER_PATH": "Runner.app",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.coralcell.leanguard",
        }

    def tearDown(self):
        self.temp.cleanup()

    def run_copy(self):
        script = Path(__file__).with_name("copy_firebase_plist.sh")
        return subprocess.run(["/bin/sh", str(script)], env=self.env, capture_output=True, text=True)

    def test_absent_config_removes_stale_build_artifact(self):
        self.output.write_text("stale public Firebase configuration")
        result = self.run_copy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.output.exists())

    def test_matching_bundle_copies_exact_sdk_configuration(self):
        data = {"BUNDLE_ID": "com.coralcell.leanguard", "PROJECT_ID": "test-project"}
        self.source.write_bytes(plistlib.dumps(data))
        result = self.run_copy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_bytes(), self.source.read_bytes())

    def test_mismatched_bundle_fails_without_copying_wrong_configuration(self):
        self.source.write_bytes(plistlib.dumps({"BUNDLE_ID": "com.example.other"}))
        result = self.run_copy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()

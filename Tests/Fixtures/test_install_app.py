#!/usr/bin/python3
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


BUILDER = Path(__file__).resolve().parents[2] / "scripts/build_dmg.sh"
BUNDLE_ID = "launcheer.kodify.vip"
QUARANTINE = "0081;6ae44970;PackagingTests;00000000-0000-0000-0000-000000000001"


class InstallerPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = tempfile.TemporaryDirectory(prefix="launcheer-package-test-")
        cls.addClassCleanup(cls.files.cleanup)
        cls.directory = Path(cls.files.name)
        code = cls.directory / "fixture.c"
        code.write_text("int main(void) { return 0; }\n")
        cls.executable = cls.directory / "Launcheer"
        subprocess.run(
            ["/usr/bin/xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=26.0",
             str(code), "-o", str(cls.executable)],
            check=True, capture_output=True, text=True, timeout=30,
        )
        cls.source = cls.directory / "Source/Launcheer.app"
        cls.create_app(cls.source)
        cls.checked = [cls.source, cls.source / "Contents/MacOS/Launcheer"]
        for path in cls.checked:
            subprocess.run(
                ["/usr/bin/xattr", "-w", "com.apple.quarantine", QUARANTINE, str(path)],
                check=True, capture_output=True, text=True,
            )
        cls.source_before = cls.snapshot(cls.source)
        cls.output = cls.directory / "Output"
        result = subprocess.run(
            ["/bin/bash", str(BUILDER), str(cls.source), str(cls.output)],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        cls.dmg = cls.output / "Launcheer-0.0.1-123-arm64.dmg"
        cls.mount = cls.directory / "Mounted"
        cls.mount.mkdir()
        subprocess.run(
            ["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
             "-mountpoint", str(cls.mount), str(cls.dmg)],
            check=True, capture_output=True, text=True, timeout=30,
        )
        cls.addClassCleanup(
            subprocess.run, ["/usr/bin/hdiutil", "detach", str(cls.mount)],
            check=True, capture_output=True, text=True, timeout=30,
        )
        cls.expanded = cls.directory / "Expanded"
        subprocess.run(
            ["/usr/sbin/pkgutil", "--expand-full", str(cls.mount / "Install Launcheer.pkg"), str(cls.expanded)],
            check=True, capture_output=True, text=True, timeout=30,
        )
        components = list(cls.expanded.rglob("PackageInfo"))
        if len(components) != 1:
            raise RuntimeError(f"Expected one component package, found: {components}")
        cls.component = components[0].parent
        cls.payload = cls.component / "Payload"
        cls.app = cls.payload / "Applications/Launcheer.app"

    @classmethod
    def create_app(cls, path, bundle_id=BUNDLE_ID):
        contents = path / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Resources").mkdir()
        shutil.copy2(cls.executable, contents / "MacOS/Launcheer")
        with (contents / "Info.plist").open("wb") as output:
            plistlib.dump({
                "CFBundleIdentifier": bundle_id,
                "CFBundleExecutable": "Launcheer",
                "CFBundleName": "Launcheer",
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "0.0.1",
                "CFBundleVersion": "123",
                "LSMinimumSystemVersion": "26.0",
            }, output)
        (contents / "Resources/fixture.txt").write_text("This app is never executed.\n")
        subprocess.run(
            ["/usr/bin/codesign", "--force", "--sign", "-", str(path)],
            check=True, capture_output=True, text=True,
        )

    @staticmethod
    def snapshot(path):
        return {
            str(file.relative_to(path)): hashlib.sha256(file.read_bytes()).hexdigest()
            for file in path.rglob("*") if file.is_file()
        }

    def test_dmg_contains_only_the_system_installer_package(self):
        self.assertEqual({path.name for path in self.mount.iterdir()}, {"Install Launcheer.pkg"})
        self.assertTrue(os.statvfs(self.mount).f_flag & os.ST_RDONLY)

    def test_payload_contains_only_the_unchanged_signed_app(self):
        self.assertEqual({path.name for path in self.payload.iterdir()}, {"Applications"})
        self.assertEqual({path.name for path in (self.payload / "Applications").iterdir()}, {"Launcheer.app"})
        self.assertEqual(self.snapshot(self.app), self.source_before)
        result = subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(self.app)],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_distribution_limits_the_target_and_requires_closing_launcheer(self):
        distribution = ET.parse(self.expanded / "Distribution").getroot()
        options = distribution.find("options")
        self.assertEqual(options.get("hostArchitectures"), "arm64")
        self.assertEqual(options.get("customize"), "never")
        self.assertEqual(options.get("require-scripts"), "false")
        domains = distribution.find("domains")
        self.assertEqual(domains.get("enable_localSystem"), "true")
        self.assertEqual(domains.get("enable_anywhere"), "false")
        self.assertEqual(domains.get("enable_currentUserHome"), "false")
        versions = distribution.findall("volume-check/allowed-os-versions/os-version")
        self.assertEqual([version.get("min") for version in versions], ["26.0"])
        refs = distribution.findall("pkg-ref")
        self.assertEqual({ref.get("id") for ref in refs}, {BUNDLE_ID + ".installer"})
        self.assertEqual([ref.get("onConclusion") for ref in refs if ref.get("onConclusion")], ["None"])
        self.assertEqual([app.get("id") for app in distribution.findall(".//must-close/app")], [BUNDLE_ID])
        self.assertEqual(distribution.findall(".//script"), [])

    def test_component_replaces_the_fixed_bundle_without_scripts_or_relocation(self):
        info = ET.parse(self.component / "PackageInfo").getroot()
        self.assertEqual(info.get("identifier"), BUNDLE_ID + ".installer")
        self.assertEqual(info.get("version"), "123")
        self.assertEqual(info.get("install-location"), "/")
        self.assertEqual(info.get("relocatable"), "false")
        relocation = info.find("relocate")
        self.assertIsNotNone(relocation)
        self.assertEqual(list(relocation), [])
        self.assertFalse(relocation.text)
        self.assertIsNone(info.find("scripts"))
        self.assertFalse((self.component / "Scripts").exists())
        upgrades = info.findall("upgrade-bundle/bundle")
        self.assertEqual([bundle.get("id") for bundle in upgrades], [BUNDLE_ID])
        bom = subprocess.check_output(["/usr/bin/lsbom", "-s", "-f", str(self.component / "Bom")], text=True)
        files = set(bom.splitlines())
        expected = {
            "./Applications/Launcheer.app/" + file for file in self.source_before
        }
        self.assertTrue(expected.issubset(files))
        for metadata in files - expected:
            path = Path(metadata)
            self.assertFalse(path.is_absolute())
            self.assertNotIn("..", path.parts)
            self.assertTrue(path.name.startswith("._"), metadata)
            self.assertTrue((self.payload / path.with_name(path.name[2:])).exists(), metadata)

    def test_payload_has_no_quarantine_and_the_source_remains_unchanged(self):
        self.assertEqual(self.snapshot(self.source), self.source_before)
        for source in self.checked:
            original = subprocess.check_output(
                ["/usr/bin/xattr", "-p", "com.apple.quarantine", str(source)], text=True,
            )
            self.assertEqual(original, QUARANTINE + "\n")
            target = self.app / source.relative_to(self.source)
            attributes = subprocess.check_output(["/usr/bin/xattr", str(target)], text=True).splitlines()
            self.assertNotIn("com.apple.quarantine", attributes)

    def test_dmg_and_checksum_are_valid_without_extra_output_files(self):
        checksum = self.dmg.with_suffix(".dmg.sha256")
        self.assertEqual({path.name for path in self.output.iterdir()}, {self.dmg.name, checksum.name})
        digest, name = checksum.read_text().split()
        self.assertEqual(name, self.dmg.name)
        self.assertEqual(digest, hashlib.sha256(self.dmg.read_bytes()).hexdigest())
        verified = subprocess.run(
            ["/usr/bin/hdiutil", "verify", str(self.dmg)],
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)

    def test_invalid_signature_and_unrelated_bundle_are_rejected(self):
        for failure in ("invalid-signature", "unrelated-bundle"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory(prefix="launcheer-package-rejected-") as temporary:
                directory = Path(temporary)
                source = directory / "Launcheer.app"
                self.create_app(source, "vip.kodify.unrelated" if failure == "unrelated-bundle" else BUNDLE_ID)
                if failure == "invalid-signature":
                    (source / "Contents/Resources/fixture.txt").write_text("Changed after signing.\n")
                    invalid = subprocess.run(
                        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(source)],
                        capture_output=True, text=True,
                    )
                    self.assertNotEqual(invalid.returncode, 0)
                before = self.snapshot(source)
                output = directory / "Output"
                result = subprocess.run(
                    ["/bin/bash", str(BUILDER), str(source), str(output)],
                    capture_output=True, text=True, timeout=30,
                )
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.snapshot(source), before)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)

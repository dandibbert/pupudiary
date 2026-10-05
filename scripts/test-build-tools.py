#!/usr/bin/env python3
"""Portable tests for build tooling; native app/XCTest runs still require macOS CI."""
import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


selection = load('select-simulators')
ipa = load('validate-ipa')
signed = load('validate-signed-ipa')


class SimulatorSelectionTests(unittest.TestCase):
    def test_selects_actual_newest_pro_and_se(self):
        data = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-18-5': [
                {'name': 'iPhone 16 Pro', 'udid': '16-pro', 'isAvailable': True},
                {'name': 'iPhone SE (3rd generation)', 'udid': 'se-old', 'isAvailable': True}],
            'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [
                {'name': 'iPhone 17 Pro Max', 'udid': '17-max', 'isAvailable': True},
                {'name': 'iPhone 17 Pro', 'udid': '17-pro', 'isAvailable': True},
                {'name': 'iPhone SE (3rd generation)', 'udid': 'se-new', 'isAvailable': True},
                {'name': 'iPhone 18 Pro', 'udid': 'unavailable', 'isAvailable': False}]
        }}
        result = selection.select_devices(data)
        self.assertEqual(result['primary']['udid'], '17-pro')
        self.assertEqual(result['compact']['udid'], 'se-new')
        self.assertEqual(result['primary']['os'], '26.2')

    def test_reports_missing_se_honestly(self):
        data = {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [
            {'name': 'iPhone 17 Pro', 'udid': 'pro', 'isAvailable': True},
            {'name': 'iPhone 17', 'udid': 'base', 'isAvailable': True}]}}
        result = selection.select_devices(data)
        self.assertEqual(result['compact']['name'], 'iPhone 17')
        self.assertIn('No iPhone SE installed', result['compact_note'])

    def test_fails_when_no_iphone_available(self):
        with self.assertRaises(ValueError):
            selection.select_devices({'devices': {}})


class IPAValidationTests(unittest.TestCase):
    def create_ipa(self, path, platform=2, include_widget=True, include_icon=True):
        # Small synthetic Mach-O is enough to exercise architecture/platform parsing.
        binary = struct.pack('<8I', 0xFEEDFACF, 0x0100000C, 0, 2, 1, 24, 0, 0)
        binary += struct.pack('<6I', 0x32, 24, platform, 17 << 16, 26 << 16, 0)
        base = {'CFBundleSupportedPlatforms': ['iPhoneOS'], 'CFBundleVersion': '1',
                'CFBundleShortVersionString': '1.0.0', 'MinimumOSVersion': '17.0'}
        app = dict(base, CFBundleIdentifier='com.dandibbert.pupudiary', CFBundleExecutable='Pupudiary',
                   CFBundleIcons={'CFBundlePrimaryIcon': {'CFBundleIconFiles': ['AppIcon60x60']}})
        widget = dict(base, CFBundleIdentifier='com.dandibbert.pupudiary.widget',
                      CFBundleExecutable='PupudiaryWidgetExtension',
                      NSExtension={'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'})
        root = 'Payload/Pupudiary.app/'
        extension = root + 'PlugIns/PupudiaryWidgetExtension.appex/'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(root + 'Info.plist', plistlib.dumps(app))
            archive.writestr(root + 'Pupudiary', binary)
            archive.writestr(root + 'Assets.car', b'synthetic catalog')
            if include_icon:
                # Header-only icon is a fixture for metadata parsing, not an actual app asset.
                archive.writestr(root + 'AppIcon60x60@3x.png', b'\x89PNG\r\n\x1a\n' + struct.pack('>I4sII', 13, b'IHDR', 180, 180))
            if include_widget:
                archive.writestr(extension + 'Info.plist', plistlib.dumps(widget))
                archive.writestr(extension + 'PupudiaryWidgetExtension', binary)

    def test_accepts_expected_unsigned_layout(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'sample.ipa'
            self.create_ipa(path)
            result = ipa.validate(path, unsigned=True)
            self.assertEqual(result['architecture'], 'arm64')
            self.assertEqual(result['icon_sizes'], [(180, 180)])

    def test_rejects_simulator_disguised_as_device(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'sample.ipa'
            self.create_ipa(path, platform=7)
            with self.assertRaisesRegex(ipa.ValidationError, 'Simulator'):
                ipa.validate(path)

    def test_rejects_missing_widget(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'sample.ipa'
            self.create_ipa(path, include_widget=False)
            with self.assertRaisesRegex(ipa.ValidationError, 'Widget .appex missing'):
                ipa.validate(path)

    def test_rejects_missing_icon(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'sample.ipa'
            self.create_ipa(path, include_icon=False)
            with self.assertRaisesRegex(ipa.ValidationError, 'icon missing'):
                ipa.validate(path)

    def test_rejects_zip_path_traversal(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'sample.ipa'
            self.create_ipa(path)
            with zipfile.ZipFile(path, 'a') as archive:
                archive.writestr('../outside', b'invalid')
            with self.assertRaisesRegex(ipa.ValidationError, 'Unsafe path'):
                ipa.validate(path)


class ProfileEntitlementTests(unittest.TestCase):
    def test_profile_wildcard_can_authorize_explicit_id(self):
        self.assertTrue(signed.permits('TEAM.com.example.*', 'TEAM.com.example.pupudiary'))
        self.assertFalse(signed.permits('TEAM.com.example.*', 'OTHER.com.example.pupudiary'))

    def test_app_group_requires_profile_membership(self):
        self.assertTrue(signed.permits(['group.shared'], ['group.shared']))
        self.assertFalse(signed.permits(['group.other'], ['group.shared']))
        self.assertFalse(signed.permits(False, True))


if __name__ == '__main__':
    unittest.main(verbosity=2)

# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reject plausible but unusable cloud-signing products before release."""
import copy
import datetime as dt
import importlib.util
from pathlib import Path
import unittest
import struct
import hashlib
import tempfile
import plistlib
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
CONTAINER = 'iCloud.com.sierraburkhart.sincitydesertdreams'
TEAM = '2LK9LNU9V8'
BUNDLE = 'com.sierraburkhart.sincitydesertdreams'

def pack(settings, extra=None, duplicate=False, corrupt_duplicate=False):
    data = b'ECFG' + struct.pack('<I', len(settings))
    for key, value in settings.items():
        name = key.encode()
        value = struct.pack('<II', 1, int(value)) if isinstance(value, bool) else struct.pack('<II', 4, len(value.encode())) + value.encode() + b'\0' * (-len(value.encode()) % 4)
        data += struct.pack('<I', len(name)) + name + struct.pack('<I', len(value)) + value
    files = {'project.binary': data, 'addons/apple_cloud/apple_cloud.cfg': b'descriptor', 'addons/apple_cloud/GODOT-CPP-LICENSE.md': b'notice'}
    files.update(extra or {})
    files = list(files.items())
    if duplicate: files.append(files[-1])
    base = 44 + sum(40 + len(n.encode()) for n, _ in files)
    directory = struct.pack('<I', len(files)); payload = b''
    for index, (name, data) in enumerate(files):
        directory += struct.pack('<I', len(name.encode())) + name.encode() + struct.pack('<QQ', base + len(payload), len(data)) + hashlib.md5(data).digest() + struct.pack('<I', 0)
        payload += (data[:-1] + b'X') if corrupt_duplicate and index == len(files) - 1 else data
    return b'GDPC' + struct.pack('<IIIIIQQ', 3, 4, 7, 2, 0, 0, 40) + directory + payload

class ExportTests(unittest.TestCase):
    def setUp(self):
        path = ROOT / 'tools/check_apple_cloud_export.py'
        self.assertTrue(path.exists(), 'Cloud export validation is missing')
        spec = importlib.util.spec_from_file_location('cloud_export', path)
        self.check = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.check)
        fixture_spec = importlib.util.spec_from_file_location('template_fixtures', Path(__file__).with_name('test_apple_cloud_macos_template.py'))
        self.template_fixtures = importlib.util.module_from_spec(fixture_spec)
        fixture_spec.loader.exec_module(self.template_fixtures)
        self.ent = {'com.apple.developer.icloud-container-identifiers': [CONTAINER],
                    'com.apple.developer.icloud-services': ['CloudKit'],
                    'com.apple.developer.icloud-container-environment': 'Production',
                    'com.apple.developer.team-identifier': TEAM,
                    'com.apple.application-identifier': TEAM + '.' + BUNDLE}
        self.profile = {'Entitlements': copy.deepcopy(self.ent), 'TeamIdentifier': [TEAM],
                        'ExpirationDate': dt.datetime(2099, 1, 1)}
        self.info = {'CFBundleIdentifier': BUNDLE, 'SCDDCloudKitEnabled': True,
                     'SCDDCloudKitContainer': CONTAINER, 'LSMinimumSystemVersionByArchitecture': {'arm64': '12.0', 'x86_64': '12.0'}}
        self.native = {'architectures': ['arm64', 'x86_64'],
                       'minimum_os': {'arm64': '12.0', 'x86_64': '12.0'}, 'platform': 'MACOS'}

    def errors(self, **kw):
        args = dict(info=self.info, entitlements=self.ent, profile=self.profile,
                    native=self.native, signed=True, distribution='developer-id', environment='Production')
        args.update(kw)
        return self.check.validate_product(**args)

    def test_valid_fixture_and_source_templates(self):
        self.assertEqual([], self.errors())
        self.assertEqual([], self.check.check_source(ROOT))

    def test_profile_service_wildcard_authorizes_only_exact_signed_cloudkit(self):
        key = 'com.apple.developer.icloud-services'
        profile = copy.deepcopy(self.profile)
        profile['Entitlements'][key] = '*'
        self.assertEqual([], self.errors(profile=profile))
        for value in ['*', ['*'], [], ['CloudDocuments'], ['CloudKit', 'CloudDocuments'], 'CloudKit', None]:
            with self.subTest(signature=value):
                ent = copy.deepcopy(self.ent); ent[key] = value
                self.assertTrue(self.errors(profile=profile, entitlements=ent))
        for value in [['*'], 'Cloud*', 'CloudKit', '', None, ['CloudKit', '*']]:
            with self.subTest(profile=value):
                profile['Entitlements'][key] = value
                self.assertTrue(self.errors(profile=profile))

    def test_profile_service_wildcard_does_not_relax_other_authorization(self):
        profile = copy.deepcopy(self.profile)
        profile['Entitlements']['com.apple.developer.icloud-services'] = '*'
        for key, value in {
            'com.apple.developer.icloud-container-identifiers': ['*'],
            'com.apple.developer.icloud-container-environment': '*',
            'com.apple.developer.team-identifier': '*',
            'com.apple.application-identifier': TEAM + '.*',
        }.items():
            with self.subTest(key=key):
                altered = copy.deepcopy(profile); altered['Entitlements'][key] = value
                self.assertTrue(self.errors(profile=altered))
        self.assertTrue(self.errors(profile=dict(profile, TeamIdentifier=['OTHER'])))
        self.assertTrue(self.errors(profile=dict(profile, ExpirationDate=dt.datetime(2000, 1, 1))))
        self.assertTrue(self.errors(profile=profile, signed=False))

    def test_profile_environment_authorizes_requested_environment_only(self):
        key = 'com.apple.developer.icloud-container-environment'
        profile = copy.deepcopy(self.profile)
        profile['Entitlements'][key] = ['Production', 'Development']
        for environment in ['Production', 'Development']:
            with self.subTest(environment=environment):
                ent = dict(self.ent); ent[key] = environment
                self.assertEqual([], self.errors(profile=profile, entitlements=ent, environment=environment))
        for value in [[], ['Development'], ['Production', '*'], ['Production', 'Unknown'], ['Production', None], '*']:
            with self.subTest(profile=value):
                altered = copy.deepcopy(profile); altered['Entitlements'][key] = value
                self.assertTrue(self.errors(profile=altered))
        for value in [['Production', 'Development'], ['Production'], '*', 'Development']:
            with self.subTest(signature=value):
                ent = dict(self.ent); ent[key] = value
                self.assertTrue(self.errors(profile=profile, entitlements=ent))

    def test_product_certificate_extraction_binds_prefix_and_requires_profile_leaf(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / 'Game.app'
            base = app / 'Contents'
            (base / 'Resources').mkdir(parents=True)
            (base / 'MacOS').mkdir()
            (base / 'Info.plist').write_bytes(plistlib.dumps(dict(self.info, CFBundleExecutable='Game')))
            (base / 'embedded.provisionprofile').write_bytes(b'profile')
            (base / 'Resources/Game.pck').write_bytes(pack({'apple_cloud/enabled': True, 'apple_cloud/container_id': CONTAINER}))
            profile = dict(self.profile, DeveloperCertificates=[b'authorized leaf'])
            strong = self.template_fixtures.dylib()
            weak = self.template_fixtures.dylib(command=0x80000018)
            cases = [(b'authorized leaf', (strong, strong), False),
                     (b'unrelated leaf', (strong, strong), True), (None, (strong, strong), True),
                     (b'authorized leaf', (strong, b''), True), (b'authorized leaf', (b'', strong), True),
                     (b'authorized leaf', (weak, strong), True)]
            for leaf, linkage, rejected in cases:
                with self.subTest(leaf=leaf, linkage=tuple(len(x) for x in linkage)):
                    (base / 'MacOS/Game').write_bytes(self.template_fixtures.universal(linkage))
                    extracted = []
                    def command(*args):
                        if args[0] == 'security': return plistlib.dumps(profile)
                        if args[0] == 'lipo': return b'arm64 x86_64'
                        if '--entitlements' in args: return plistlib.dumps(self.ent)
                        if args[:2] == ('codesign', '-d'):
                            # codesign's optional prefix must be attached; otherwise
                            # it treats the bare prefix as another inspected path.
                            self.assertEqual(4, len(args))
                            self.assertTrue(args[2].startswith('--extract-certificates='))
                            self.assertEqual(str(app), args[3])
                            prefix = args[2].split('=', 1)[1]
                            extracted.append(prefix)
                            if leaf is not None: Path(prefix + '0').write_bytes(leaf)
                        return b''
                    detail = SimpleNamespace(stderr=('Authority=Developer ID Application: Example\nTeamIdentifier=' + TEAM).encode())
                    with patch.object(self.check, 'command', side_effect=command), patch.object(self.check.subprocess, 'run', return_value=detail), patch.object(self.check, 'inspect_native', return_value=self.native):
                        errors = self.check.inspect_product(app, 'developer-id', 'Production')
                    self.assertEqual(1, len(extracted))
                    self.assertEqual(rejected, bool(errors))
                    if leaf != b'authorized leaf': self.assertTrue(any('Signature' in error for error in errors))

    def test_actual_main_linkage_is_checked_per_architecture_not_native_bridge(self):
        self.assertTrue(hasattr(self.check, 'inspect_main_cloudkit'), 'Main executable CloudKit dependency check missing')
        with tempfile.TemporaryDirectory() as temp:
            executable = Path(temp) / 'Game'
            strong = self.template_fixtures.dylib()
            for extras, rejected in [((strong, strong), False), ((strong, b''), True),
                                     ((b'', strong), True), ((strong + strong, strong), True),
                                     ((self.template_fixtures.dylib(command=0x80000018), strong), True)]:
                with self.subTest(linkage=tuple(len(x) for x in extras)):
                    executable.write_bytes(self.template_fixtures.universal(extras))
                    self.assertEqual(rejected, bool(self.check.inspect_main_cloudkit(executable)))

    def test_container_environment_service_must_match_product_and_profile(self):
        for key, values in {
            'com.apple.developer.icloud-container-identifiers': [[], [CONTAINER, 'iCloud.other']],
            'com.apple.developer.icloud-services': [[], ['CloudDocuments']],
            'com.apple.developer.icloud-container-environment': ['Development', ''],
            'com.apple.developer.team-identifier': ['OTHER'],
            'com.apple.application-identifier': ['OTHER.wrong'],
        }.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    ent = copy.deepcopy(self.ent); ent[key] = value
                    self.assertTrue(self.errors(entitlements=ent))
                    profile = copy.deepcopy(self.profile); profile['Entitlements'][key] = value
                    self.assertTrue(self.errors(profile=profile))

    def test_unsigned_missing_library_expired_profile_and_sealed_flags_rejected(self):
        self.assertTrue(self.errors(signed=False))
        self.assertTrue(self.errors(native=None))
        self.assertTrue(self.errors(profile=None))
        expired = copy.deepcopy(self.profile); expired['ExpirationDate'] = dt.datetime(2000, 1, 1)
        self.assertTrue(self.errors(profile=expired))
        for key, value in [('SCDDCloudKitEnabled', False), ('SCDDCloudKitEnabled', 'true'),
                           ('SCDDCloudKitContainer', 'iCloud.other'), ('CFBundleIdentifier', 'wrong')]:
            info = dict(self.info); info[key] = value
            self.assertTrue(self.errors(info=info))

    def test_platform_architecture_and_minimum_os_must_match(self):
        for native in [dict(self.native, architectures=['arm64']),
                       dict(self.native, platform='IOSSIMULATOR'),
                       dict(self.native, minimum_os={'arm64': '11.0', 'x86_64': '12.0'}),
                       dict(self.native, minimum_os={'arm64': '13.0', 'x86_64': '12.0'})]:
            self.assertTrue(self.errors(native=native))
        ios = {'architectures': ['arm64'], 'minimum_os': {'arm64': '17.0'}, 'platform': 'IOS'}
        ent = dict(self.ent); ent['application-identifier'] = ent.pop('com.apple.application-identifier')
        profile = dict(self.profile, Entitlements=ent)
        self.assertEqual([], self.errors(native=ios, distribution='ios', entitlements=ent, profile=profile, info=dict(self.info, MinimumOSVersion='17.0')))

    def test_release_rejects_debug_entitlement_and_wrong_app_minimum(self):
        self.assertTrue(self.errors(entitlements=dict(self.ent, **{'get-task-allow': True})))
        self.assertTrue(self.errors(info=dict(self.info, LSMinimumSystemVersionByArchitecture={'arm64': '10.15', 'x86_64': '12.0'})))
        self.assertTrue(self.errors(info=dict(self.info, LSMinimumSystemVersionByArchitecture={'arm64': '14.0', 'x86_64': '12.0'})))

    def test_store_requires_sandbox_and_development_is_explicit(self):
        self.assertTrue(self.errors(distribution='mac-app-store'))
        ent = dict(self.ent, **{'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True})
        self.assertEqual([], self.errors(distribution='mac-app-store', entitlements=ent))
        ent = dict(self.ent); ent['com.apple.developer.icloud-container-environment'] = 'Development'
        profile = dict(self.profile, Entitlements=ent)
        self.assertEqual([], self.errors(environment='Development', entitlements=ent, profile=profile))

    def test_pack_inspection_checks_actual_settings_and_keeps_signing_inputs_out(self):
        self.assertTrue(hasattr(self.check, 'inspect_pack'), 'Actual exported pack inspection missing')
        settings = {'apple_cloud/enabled': True, 'apple_cloud/container_id': CONTAINER}
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'game.pck'
            path.write_bytes(pack(settings))
            self.assertEqual([], self.check.inspect_pack(path))
            path.write_bytes(pack(settings, duplicate=True))
            self.assertEqual([], self.check.inspect_pack(path))
            for wrong in [dict(settings, **{'apple_cloud/enabled': False}), dict(settings, **{'apple_cloud/container_id': 'wrong'})]:
                path.write_bytes(pack(wrong)); self.assertTrue(self.check.inspect_pack(path))
            for name in ['addons/apple_cloud/bin/libSCDDAppleCloud.dylib', 'embedded.provisionprofile', 'private.entitlements']:
                path.write_bytes(pack(settings, {name: b'private'})); self.assertTrue(self.check.inspect_pack(path))
            path.write_bytes(pack(settings, duplicate=True, corrupt_duplicate=True))
            with self.assertRaises(ValueError): self.check.inspect_pack(path)
            path.write_bytes(b'GDPC')
            with self.assertRaises(ValueError): self.check.inspect_pack(path)

    def test_rejects_packed_default_settings_override(self):
        settings = {'apple_cloud/enabled': True, 'apple_cloud/container_id': CONTAINER}
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'game.pck'
            for name in ['override.cfg', 'res://override.cfg', './override.cfg', 'nested/../override.cfg']:
                with self.subTest(name=name):
                    path.write_bytes(pack(settings, {name: b'[apple_cloud]\nenabled=false\n'}))
                    self.assertTrue(self.check.inspect_pack(path), 'Packed override changes actual runtime settings')

    def test_rejects_custom_settings_override_routes(self):
        settings = {'apple_cloud/enabled': True, 'apple_cloud/container_id': CONTAINER}
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'game.pck'
            for suffix in ['', '.macos', '.ios']:
                for value in ['res://cloud.cfg', '/private/cloud.cfg', 'user://cloud.cfg', 'cloud.cfg']:
                    with self.subTest(suffix=suffix, value=value):
                        path.write_bytes(pack(dict(settings, **{'application/config/project_settings_override' + suffix: value})))
                        self.assertTrue(self.check.inspect_pack(path), 'Custom override is not certified by project.binary')
            path.write_bytes(pack(dict(settings, **{'application/config/project_settings_override': ''})))
            self.assertEqual([], self.check.inspect_pack(path))

    def test_rejects_pack_and_executable_sibling_override_files(self):
        settings = {'apple_cloud/enabled': True, 'apple_cloud/container_id': CONTAINER}
        with tempfile.TemporaryDirectory() as temp:
            for ios in [False, True]:
                with self.subTest(ios=ios):
                    app = Path(temp) / ('iOS.app' if ios else 'Mac.app')
                    resources = app if ios else app / 'Contents/Resources'
                    executable = app / 'Game' if ios else app / 'Contents/MacOS/Game'
                    resources.mkdir(parents=True); executable.parent.mkdir(parents=True, exist_ok=True)
                    path = resources / 'Game.pck'; path.write_bytes(pack(settings))
                    # Exercise the product inspection boundary's actual selected executable path.
                    for override in {path.parent / 'override.cfg', executable.parent / 'override.cfg'}:
                        override.write_text('[apple_cloud]\nenabled=false\n')
                        if override.parent == path.parent:
                            self.assertTrue(self.check.inspect_pack(path), 'Explicit main-pack sibling override allowed')
                        else:
                            # New argument extends inspection to the ordinary executable startup route.
                            self.assertTrue(self.check.inspect_pack(path, executable_path=executable))
                        override.unlink()
                    self.assertEqual([], self.check.inspect_pack(path, executable_path=executable))

if __name__ == '__main__': unittest.main()

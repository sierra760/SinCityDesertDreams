#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate source templates or an actual pre-submission signed Apple .app.

No Apple account access. Source success is never provisioning/server evidence.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import plistlib
import posixpath
import re
import subprocess
import sys
import struct
import hashlib
import io
import tempfile
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
CONTAINER = 'iCloud.com.sierraburkhart.sincitydesertdreams'
BUNDLE = 'com.sierraburkhart.sincitydesertdreams'
TEAM = '2LK9LNU9V8'
CUSTOM_OVERRIDE = 'application/config/project_settings_override'


def validate_product(*, info, entitlements, profile, native, signed,
                     distribution, environment='Production'):
    """Validate decoded evidence; inspectors, never caller assertions, supply CLI evidence."""
    errors = []
    def require(ok, message):
        if not ok: errors.append(message)
    require(signed, 'Signature is missing, ad-hoc, invalid, or has the wrong signing authority/team')
    require(info.get('CFBundleIdentifier') == BUNDLE, 'Wrong bundle identifier')
    require(info.get('SCDDCloudKitEnabled') is True, 'Sealed SCDDCloudKitEnabled must be Boolean true')
    require(info.get('SCDDCloudKitContainer') == CONTAINER, 'Wrong sealed cloud container')
    app_key = 'application-identifier' if distribution == 'ios' else 'com.apple.application-identifier'
    expected = {'com.apple.developer.icloud-container-identifiers': [CONTAINER],
                'com.apple.developer.icloud-services': ['CloudKit'],
                'com.apple.developer.icloud-container-environment': environment,
                'com.apple.developer.team-identifier': TEAM, app_key: TEAM + '.' + BUNDLE}
    for label, ent in [('signature', entitlements), ('profile', (profile or {}).get('Entitlements', {}))]:
        for key, value in expected.items():
            # TN2415: profiles may authorize iCloud services with the string '*'.
            # The app signature must still request exactly our CloudKit service.
            if label == 'profile' and key == 'com.apple.developer.icloud-services' and ent.get(key) == '*':
                continue
            if label == 'profile' and key == 'com.apple.developer.icloud-container-environment' and isinstance(ent.get(key), list):
                allowed = ent[key]
                require(value in allowed and all(item in ('Development', 'Production') for item in allowed),
                        f'profile: {key} must authorize {value!r} using recognized environments')
                continue
            require(ent.get(key) == value, f'{label}: {key} must equal {value!r}')
    require(profile is not None, 'Missing embedded provisioning profile (required for pre-submission verification)')
    if profile:
        require(profile.get('TeamIdentifier') == [TEAM], 'Wrong profile team')
        expires = profile.get('ExpirationDate')
        require(isinstance(expires, dt.datetime) and expires.replace(tzinfo=dt.timezone.utc) > dt.datetime.now(dt.timezone.utc), 'Expired or invalid profile expiry')
    if distribution == 'ios':
        require(info.get('MinimumOSVersion') == '17.0', 'Wrong application minimum OS')
    else:
        require(info.get('LSMinimumSystemVersionByArchitecture') == {'arm64': '12.0', 'x86_64': '12.0'}, 'Wrong application minimum OS by architecture')
    if environment == 'Production':
        require(not entitlements.get('get-task-allow', False) and not entitlements.get('com.apple.security.get-task-allow', False), 'Production app must not allow debugging')
    if distribution == 'mac-app-store':
        require(entitlements.get('com.apple.security.app-sandbox') is True, 'Mac App Store requires sandbox')
        require(entitlements.get('com.apple.security.network.client') is True, 'Mac App Store requires outgoing network access')
    require(native is not None, 'Missing packaged SCDDAppleCloud library')
    if native:
        ios = distribution == 'ios'
        archs = ['arm64'] if ios else ['arm64', 'x86_64']
        require(sorted(native.get('architectures', [])) == archs, 'Wrong native architectures')
        require(native.get('platform') == ('IOS' if ios else 'MACOS'), 'Wrong native platform (simulators are unsupported)')
        minimum = 17.0 if ios else 12.0
        for arch in archs:
            value = native.get('minimum_os', {}).get(arch, '')
            require(value in (str(minimum), str(int(minimum)), str(minimum) + '.0'), f'Wrong native minimum OS for {arch}: {value}')
    return errors


def sections(path):
    result = {}; current = None
    for line in path.read_text().splitlines():
        match = re.fullmatch(r'\[([^]]+)\]', line)
        if match:
            current = result.setdefault(match[1], {})
        elif current is not None and '=' in line and not line.startswith(';'):
            key, value = line.split('=', 1)
            current[key] = value
    return result


def check_source(root=ROOT):
    errors = []
    def require(ok, message):
        if not ok: errors.append(message)
    project = sections(root / 'game/project.godot')
    require(project.get('apple_cloud', {}).get('enabled') == 'false', 'Tracked project must keep unprovisioned cloud disabled')
    require(project.get('apple_cloud', {}).get('container_id') == json.dumps(CONTAINER), 'Wrong project container')
    require('res://addons/apple_cloud/plugin.cfg' in project.get('editor_plugins', {}).get('enabled', ''), 'Cloud exporter is not enabled')
    presets = sections(root / 'game/export_presets.cfg')
    macs = []
    for section, preset in presets.items():
        if not re.fullmatch(r'preset\.\d+', section): continue
        options = presets.get(section + '.options', {})
        if preset.get('platform') == '"macOS"':
            macs.append((preset, options))
            require(options.get('codesign/entitlements/custom_file', '""') == '""', 'Never point Godot cleanup at a tracked custom entitlement file')
            require(options.get('binary_format/architecture') == '"universal"', 'Mac requires universal architecture')
            for arch in ['arm64', 'x86_64']:
                require(options.get('application/min_macos_version_' + arch) == '"12.0"', 'Mac plist minimum must match native minimum 12.0')
        if preset.get('platform') in ['"macOS"', '"iOS"']:
            fragment = json.loads(options.get('application/additional_plist_content', '""'))
            try: info = plistlib.loads(('<plist><dict>' + fragment + '</dict></plist>').encode())
            except Exception: info = {}
            require(info.get('SCDDCloudKitEnabled') is False and info.get('SCDDCloudKitContainer') == CONTAINER, 'Unconfigured Apple presets require sealed disabled flags')
    dmg = [(p, o) for p, o in macs if p.get('name') == '"macOS"']
    store = [(p, o) for p, o in macs if p.get('name') == '"macOS App Store"']
    require(len(dmg) == 1 and dmg[0][1].get('export/distribution_type') == '1' and dmg[0][0].get('export_path', '').endswith('.dmg"'), 'Preserve Developer ID DMG route')
    require(len(store) == 1 and store[0][1].get('export/distribution_type') == '2' and store[0][1].get('codesign/entitlements/app_sandbox/enabled') == 'true' and store[0][0].get('export_path', '').endswith('.pkg"'), 'Separate sandboxed Mac App Store PKG preset required')
    for name in ['developer-id', 'mac-app-store']:
        for suffix, env in [('', 'Production'), ('-development', 'Development')]:
            path = root / f'game/platform/apple-cloud/{name}{suffix}.entitlements'
            if not path.is_file():
                errors.append(f'Missing entitlement template: {path.name}'); continue
            ent = plistlib.loads(path.read_bytes())
            for key, value in [('com.apple.developer.icloud-container-identifiers', [CONTAINER]), ('com.apple.developer.icloud-services', ['CloudKit']), ('com.apple.developer.icloud-container-environment', env)]:
                require(ent.get(key) == value, f'{path.name}: wrong {key}')
            require(ent.get('com.apple.security.app-sandbox', False) is (name == 'mac-app-store'), f'{path.name}: wrong sandbox mode')
    for relative in ['addons/apple_cloud/plugin.cfg', 'addons/apple_cloud/plugin.gd', 'addons/apple_cloud/export_plugin.gd', 'addons/apple_cloud/apple_cloud.cfg', 'addons/apple_cloud/GODOT-CPP-LICENSE.md', 'addons/apple_cloud/bin/libSCDDAppleCloud.dylib', 'addons/apple_cloud/bin/SCDDAppleCloud.framework/SCDDAppleCloud']:
        require((root / 'game' / relative).is_file(), f'Missing export input: {relative}')
    return errors


def command(*args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode: raise ValueError(f'{args[0]} failed: {result.stderr.decode(errors="replace").strip()}')
    return result.stdout


def inspect_native(path):
    if not path.is_file(): return None
    architectures = command('lipo', '-archs', str(path)).decode().split()
    minimum_os = {}; platforms = set()
    for arch in architectures:
        text = command('xcrun', 'vtool', '-arch', arch, '-show-build', str(path)).decode()
        platforms.update(re.findall(r'\bplatform\s+(\w+)', text))
        values = re.findall(r'\bminos\s+([\d.]+)', text)
        minimum_os[arch] = values[0] if len(values) == 1 else ''
    return dict(architectures=architectures, minimum_os=minimum_os, platform=next(iter(platforms)) if len(platforms) == 1 else '')


def inspect_main_cloudkit(path):
    """The native bridge's linkage does not grant the main app's sandbox access."""
    spec = importlib.util.spec_from_file_location('cloud_macos_template', Path(__file__).with_name('prepare_apple_cloud_macos_template.py'))
    template = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(template)
    try:
        if not path.is_file() or path.stat().st_size > template.MAX_ENTRY_BYTES:
            raise ValueError('Missing or oversized main executable')
        with path.open('rb') as stream:
            data = stream.read(template.MAX_ENTRY_BYTES + 1)
        template.inspect_macos_main(data)
    except (OSError, ValueError) as error:
        return ['Main executable CloudKit linkage: ' + str(error)]
    return []


def read_exact(stream, length):
    if length < 0 or length > 16 * 1024 * 1024: raise ValueError('Invalid pack field length')
    data = stream.read(length)
    if len(data) != length: raise ValueError('Truncated pack/configuration')
    return data


def uint32(stream):
    return struct.unpack('<I', read_exact(stream, 4))[0]


def cloud_settings(data):
    stream = io.BytesIO(data)
    if read_exact(stream, 4) != b'ECFG': raise ValueError('Not a binary Godot configuration')
    count = uint32(stream)
    if count > 100000: raise ValueError('Unbounded project configuration')
    result = {}
    for _ in range(count):
        key = read_exact(stream, uint32(stream)).decode('utf-8')
        value = read_exact(stream, uint32(stream))
        if not (key.startswith('apple_cloud/') or key == CUSTOM_OVERRIDE or key.startswith(CUSTOM_OVERRIDE + '.')): continue
        if key in result: raise ValueError('Duplicate cloud project setting')
        if len(value) == 8 and struct.unpack('<I', value[:4])[0] == 1:
            result[key] = struct.unpack('<I', value[4:])[0] == 1
        elif len(value) >= 8 and struct.unpack('<I', value[:4])[0] == 4:
            length = struct.unpack('<I', value[4:8])[0]
            if length > len(value) - 8: raise ValueError('Truncated cloud string setting')
            result[key] = value[8:8+length].decode('utf-8')
        else: result[key] = None
    return result


def inspect_pack(path, require_enabled=True, executable_path=None):
    """Read the actual unencrypted standalone Godot 4.7 pack, without launching it.

    Layout: Godot core/io/file_access_pack.cpp and core/config/project_settings.cpp.
    Unsupported encryption, patches, sparse packs and settings overrides fail closed.
    """
    errors = []; entries = {}; ranges = []; size = path.stat().st_size
    # Godot 4.7.2 _setup loads override.cfg beside an explicit main pack,
    # or from the PCK and executable directory during ordinary app startup.
    override_locations = {path.parent / 'override.cfg'}
    if executable_path is not None:
        override_locations.add(executable_path.parent / 'override.cfg')
    for override in sorted(override_locations):
        if override.exists() or override.is_symlink():
            errors.append('External ProjectSettings override is unsupported: ' + str(override))
    with path.open('rb') as stream:
        if read_exact(stream, 4) != b'GDPC': raise ValueError('Not a standalone Godot PCK')
        version = uint32(stream)
        read_exact(stream, 12)  # Engine version.
        flags = uint32(stream)
        if version not in (2, 3, 4) or flags & ~2: raise ValueError('Unsupported pack version/flags')
        base = struct.unpack('<Q', read_exact(stream, 8))[0]
        if version >= 3:
            directory = struct.unpack('<Q', read_exact(stream, 8))[0]
            if directory > size: raise ValueError('Invalid pack directory offset')
            stream.seek(directory)
        else: read_exact(stream, 64)
        directory_start = stream.tell()
        count = uint32(stream)
        if count > 100000: raise ValueError('Unbounded pack directory')
        for _ in range(count):
            name = read_exact(stream, uint32(stream)).rstrip(b'\0').decode('utf-8').removeprefix('res://')
            offset, length = struct.unpack('<QQ', read_exact(stream, 16))
            digest = read_exact(stream, 16); file_flags = uint32(stream)
            if file_flags or base + offset + length > size: raise ValueError('Invalid/encrypted pack entry')
            if name in entries:
                prior_offset, prior_length, prior_digest = entries[name]
                if (prior_length, prior_digest) != (length, digest): raise ValueError('Conflicting duplicate pack entry')
                directory_position = stream.tell()
                remaining = length; checked = 0
                while remaining:
                    chunk = min(65536, remaining)
                    stream.seek(prior_offset + checked); first = read_exact(stream, chunk)
                    stream.seek(base + offset + checked); second = read_exact(stream, chunk)
                    if first != second: raise ValueError('Duplicate pack payload bytes differ')
                    checked += chunk; remaining -= chunk
                stream.seek(directory_position)
            # Godot repeats the boot splash with identical bytes; last entry wins.
            if length: ranges.append((base + offset, base + offset + length))
            entries[name] = (base + offset, length, digest)
            if posixpath.normpath(name.replace('\\', '/')) == 'override.cfg':
                errors.append('Packed ProjectSettings override is unsupported: ' + name)
            if name.startswith('addons/apple_cloud/bin/') or name.endswith(('.entitlements', '.provisionprofile', '.mobileprovision')):
                errors.append('Native/signing input inside PCK: ' + name)
        directory_end = stream.tell()
        previous_end = 0
        for start, end in sorted(ranges):
            if start < 40 or start < previous_end or (start < directory_end and end > directory_start): raise ValueError('Overlapping pack payload/directory/header')
            previous_end = end
        for name in ['project.binary', 'addons/apple_cloud/apple_cloud.cfg', 'addons/apple_cloud/GODOT-CPP-LICENSE.md']:
            if name not in entries: errors.append('Missing packed resource: ' + name)
        if 'project.binary' in entries:
            offset, length, digest = entries['project.binary']; stream.seek(offset)
            data = read_exact(stream, length)
            if hashlib.md5(data).digest() != digest: raise ValueError('Corrupt packed project settings')
            settings = cloud_settings(data)
            # setup() may load a custom local, res://, user:// or absolute path
            # after defaults; reject every nonempty/malformed selector, including
            # feature-qualified selectors, rather than execute or interpret it.
            for key in list(settings):
                if key == CUSTOM_OVERRIDE or key.startswith(CUSTOM_OVERRIDE + '.'):
                    if settings.pop(key) != '': errors.append('Custom ProjectSettings override is unsupported: ' + key)
            if settings.get('apple_cloud/enabled') is not require_enabled: errors.append('Packed apple_cloud/enabled does not match expected state')
            if settings.get('apple_cloud/container_id') != CONTAINER: errors.append('Wrong packed apple_cloud/container_id')
            if set(settings) != {'apple_cloud/enabled', 'apple_cloud/container_id'}: errors.append('Unexpected cloud overrides/settings')
    return errors


def inspect_product(path, distribution, environment):
    if path.suffix != '.app' or not path.is_dir(): raise ValueError('--product must be an extracted .app, not a DMG, PKG, IPA or Xcode project')
    ios = distribution == 'ios'
    base = path if ios else path / 'Contents'
    info = plistlib.loads((base / 'Info.plist').read_bytes())
    native_path = base / ('Frameworks/SCDDAppleCloud.framework/SCDDAppleCloud' if ios else 'Frameworks/libSCDDAppleCloud.dylib')
    signed = False; entitlements = {}
    try:
        command('codesign', '--verify', '--deep', '--strict', str(path))
        detail = subprocess.run(['codesign', '-dvv', str(path)], capture_output=True).stderr.decode()
        authority = 'Developer ID Application:' if distribution == 'developer-id' else ('Apple Development:' if environment == 'Development' else 'Apple Distribution:')
        # Mac App Store older distribution certificate naming is still valid.
        correct_authority = authority in detail or (distribution == 'mac-app-store' and environment == 'Production' and '3rd Party Mac Developer Application:' in detail)
        signed = 'Signature=adhoc' not in detail and 'TeamIdentifier=' + TEAM in detail and correct_authority
        entitlements = plistlib.loads(command('codesign', '-d', '--entitlements', ':-', str(path)))
    except (ValueError, plistlib.InvalidFileException): pass
    profile_path = base / ('embedded.mobileprovision' if ios else 'embedded.provisionprofile')
    profile = plistlib.loads(command('security', 'cms', '-D', '-i', str(profile_path))) if profile_path.is_file() else None
    if signed and profile:
        with tempfile.TemporaryDirectory(prefix='scdd-signature-check-') as temp:
            prefix = str(Path(temp) / 'certificate')
            command('codesign', '-d', '--extract-certificates=' + prefix, str(path))
            leaf = Path(prefix + '0')
            signed = leaf.is_file() and leaf.read_bytes() in profile.get('DeveloperCertificates', [])
    errors = validate_product(info=info, entitlements=entitlements, profile=profile, native=inspect_native(native_path), signed=signed, distribution=distribution, environment=environment)
    executable = None
    executable_name = info.get('CFBundleExecutable', '')
    if not executable_name or '/' in executable_name: errors.append('Invalid app executable name')
    else:
        executable = base / executable_name if ios else base / 'MacOS' / executable_name
        architectures = command('lipo', '-archs', str(executable)).decode().split()
        if sorted(architectures) != (['arm64'] if ios else ['arm64', 'x86_64']): errors.append('Wrong main executable architectures')
        if not ios: errors.extend(inspect_main_cloudkit(executable))
    packs = list((base if ios else base / 'Resources').glob('*.pck'))
    if len(packs) != 1: errors.append('Expected exactly one packaged standalone PCK')
    else: errors.extend(inspect_pack(packs[0], executable_path=executable))
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--source', action='store_true')
    modes.add_argument('--product', type=Path)
    parser.add_argument('--distribution', choices=['developer-id', 'mac-app-store', 'ios'])
    parser.add_argument('--environment', choices=['Development', 'Production'], default='Production')
    args = parser.parse_args(argv)
    if args.product and not args.distribution: parser.error('--product requires --distribution')
    try: errors = check_source() if args.source else inspect_product(args.product, args.distribution, args.environment)
    except (OSError, ValueError, plistlib.InvalidFileException) as exc: errors = [str(exc)]
    for error in errors: print('FAIL:', error)
    if not errors: print('PASS: source templates only; account registration remains unverified' if args.source else 'PASS: signed product packaging; account/schema/device verification remains separate')
    return 1 if errors else 0

if __name__ == '__main__': sys.exit(main())

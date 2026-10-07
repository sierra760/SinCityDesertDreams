#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Build the unsigned Apple sharing libraries into game/addons/apple_share/bin:
a universal macOS dylib and an arm64 iOS framework. Requires macOS with Xcode,
SCons and the pinned godot-cpp checkout.
"""
import argparse
import pathlib
import plistlib
import shutil
import subprocess

GODOT_CPP_REVISION = 'e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77'  # godot-4.5-stable

parser = argparse.ArgumentParser()
parser.add_argument('--godot-cpp', type=pathlib.Path, required=True)
parser.add_argument('--scons', required=True)
args = parser.parse_args()

source = pathlib.Path(__file__).resolve().parent
cpp = args.godot_cpp.resolve()
revision = subprocess.check_output(['git', '-C', str(cpp), 'rev-parse', 'HEAD'], text=True).strip()
if revision != GODOT_CPP_REVISION:
    raise SystemExit('Use the documented official godot-4.5-stable bindings revision.')

out = source.parents[1] / 'game/addons/apple_share/bin'
out.mkdir(parents=True, exist_ok=True)

for platform, arch, sdk in [('macos', 'universal', 'macosx'), ('ios', 'arm64', 'iphoneos')]:
    # Static godot-cpp library for this platform.
    cmd = [args.scons, '-C', str(cpp), f'platform={platform}', 'target=template_release',
           f'arch={arch}', f'build_profile={source / "build_profile.json"}', '-j4']
    if platform == 'ios':
        cmd.append('ios_min_version=16.0')
    else:
        cmd.append('macos_deployment_target=12.0')
    subprocess.run(cmd, check=True)

    sdk_path = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
    includes = ['-I' + str(cpp / x) for x in ['include', 'gen/include', 'gdextension']]
    library = cpp / 'bin' / f'libgodot-cpp.{platform}.template_release.{arch}.a'
    if platform == 'macos':
        target = out / 'libSCDDNativeShare.dylib'
        architectures = ['-arch', 'arm64', '-arch', 'x86_64']
        ui_framework = 'AppKit'
    else:
        target = out / 'SCDDNativeShare.framework/SCDDNativeShare'
        architectures = ['-arch', 'arm64']
        ui_framework = 'UIKit'
    target.parent.mkdir(parents=True, exist_ok=True)

    cmd = ['xcrun', '--sdk', sdk, 'clang++', '-std=c++17', '-fobjc-arc', '-fvisibility=hidden',
           '-dynamiclib', *architectures, '-isysroot', sdk_path, *includes,
           str(source / 'apple_share.mm'), str(library),
           '-framework', 'Foundation', '-framework', 'CoreGraphics', '-framework', ui_framework,
           '-o', str(target)]
    if platform == 'macos':
        cmd += ['-mmacosx-version-min=12.0', '-Wl,-install_name,@rpath/libSCDDNativeShare.dylib']
    else:
        cmd += ['-miphoneos-version-min=16.0',
                '-Wl,-install_name,@rpath/SCDDNativeShare.framework/SCDDNativeShare']
    subprocess.run(cmd, check=True)

    if platform == 'ios':
        info = {
            'CFBundleExecutable': 'SCDDNativeShare',
            'CFBundleIdentifier': 'com.sierraburkhart.sincitydesertdreams.share',
            'CFBundleName': 'SCDDNativeShare',
            'CFBundlePackageType': 'FMWK',
            'CFBundleShortVersionString': '1.0',
            'CFBundleVersion': '1',
            'MinimumOSVersion': '16.0',
            'CFBundleSupportedPlatforms': ['iPhoneOS'],
        }
        with (target.parent / 'Info.plist').open('wb') as f:
            plistlib.dump(info, f)

shutil.copyfile(cpp / 'LICENSE.md', source / 'GODOT-CPP-LICENSE.md')
print('Built unsigned macOS universal and iOS arm64 native libraries.')

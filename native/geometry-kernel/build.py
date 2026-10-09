#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Build the unsigned geometry-kernel libraries into game/addons/scdd_geometry/bin:
a universal macOS dylib, an arm64 iOS framework and an x86_64 Windows DLL.
Requires macOS with Xcode, MinGW-w64 (`brew install mingw-w64`) and the pinned
godot-cpp checkout with its template_release static libraries (built with
native/apple-share/build_profile.json; Windows with use_mingw=yes).
-ffp-contract=off keeps float32 vector arithmetic identical to the engine's own
uncontracted expressions, so native and GDScript results match bit for bit; the
Windows build also targets baseline x86_64 (no FMA instructions exist to contract).
"""
import argparse
import pathlib
import plistlib
import shutil
import subprocess

GODOT_CPP_REVISION = 'e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77'  # godot-4.5-stable

parser = argparse.ArgumentParser()
parser.add_argument('--godot-cpp', type=pathlib.Path, required=True)
parser.add_argument('--scons',
                    help='Only used to build a missing godot-cpp static library with the shared build profile.')
parser.add_argument('--platform', action='append', choices=['macos', 'ios', 'windows'],
                    help='Build only these libraries (repeatable); default builds all three.')
args = parser.parse_args()
platforms = args.platform or ['macos', 'ios', 'windows']

source = pathlib.Path(__file__).resolve().parent
cpp = args.godot_cpp.resolve()
revision = subprocess.check_output(['git', '-C', str(cpp), 'rev-parse', 'HEAD'], text=True).strip()
if revision != GODOT_CPP_REVISION:
    raise SystemExit('Use the documented official godot-4.5-stable bindings revision.')

out = source.parents[1] / 'game/addons/scdd_geometry/bin'
out.mkdir(parents=True, exist_ok=True)
profile = source.parent / 'apple-share' / 'build_profile.json'
# Error macros embed __FILE__; keep private checkout paths out of the binaries.
prefix_maps = [f'-ffile-prefix-map={source.parents[1]}=.', f'-ffile-prefix-map={cpp}=godot-cpp']

for platform, arch, sdk in [('macos', 'universal', 'macosx'), ('ios', 'arm64', 'iphoneos')]:
    if platform not in platforms:
        continue
    library = cpp / 'bin' / f'libgodot-cpp.{platform}.template_release.{arch}.a'
    if not library.exists():
        if not args.scons:
            raise SystemExit(f'Missing {library}; pass --scons to build it with {profile}.')
        cmd = [args.scons, '-C', str(cpp), f'platform={platform}', 'target=template_release',
               f'arch={arch}', f'build_profile={profile}', '-j4']
        cmd.append('ios_min_version=16.0' if platform == 'ios' else 'macos_deployment_target=12.0')
        subprocess.run(cmd, check=True)

    sdk_path = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
    includes = ['-I' + str(cpp / x) for x in ['include', 'gen/include', 'gdextension']]
    if platform == 'macos':
        target = out / 'libSCDDGeometry.dylib'
        architectures = ['-arch', 'arm64', '-arch', 'x86_64']
    else:
        target = out / 'SCDDGeometry.framework/SCDDGeometry'
        architectures = ['-arch', 'arm64']
    target.parent.mkdir(parents=True, exist_ok=True)

    cmd = ['xcrun', '--sdk', sdk, 'clang++', '-std=c++17', '-O2', '-ffp-contract=off',
           '-fvisibility=hidden', *prefix_maps, '-dynamiclib', *architectures, '-isysroot', sdk_path, *includes,
           str(source / 'geometry_kernel.cpp'), str(library), '-o', str(target)]
    if platform == 'macos':
        cmd += ['-mmacosx-version-min=12.0', '-Wl,-install_name,@rpath/libSCDDGeometry.dylib']
    else:
        cmd += ['-miphoneos-version-min=16.0', '-Wl,-install_name,@rpath/SCDDGeometry.framework/SCDDGeometry']
    subprocess.run(cmd, check=True)

    if platform == 'ios':
        info = {
            'CFBundleExecutable': 'SCDDGeometry',
            'CFBundleIdentifier': 'com.sierraburkhart.sincitydesertdreams.geometry',
            'CFBundleName': 'SCDDGeometry',
            'CFBundlePackageType': 'FMWK',
            'CFBundleShortVersionString': '1.0',
            'CFBundleVersion': '1',
            'MinimumOSVersion': '16.0',
            'CFBundleSupportedPlatforms': ['iPhoneOS'],
        }
        with (target.parent / 'Info.plist').open('wb') as f:
            plistlib.dump(info, f)

# Windows: MinGW-w64 cross build, C++ runtime linked statically so the DLL needs
# only KERNEL32 and the Universal CRT that ships with Windows 10 and later.
if 'windows' in platforms:
    library = cpp / 'bin' / 'libgodot-cpp.windows.template_release.x86_64.a'
    if not library.exists():
        if not args.scons:
            raise SystemExit(f'Missing {library}; pass --scons to build it with {profile}.')
        subprocess.run([args.scons, '-C', str(cpp), 'platform=windows', 'target=template_release', 'arch=x86_64',
                        'use_mingw=yes', f'build_profile={profile}', '-j4'], check=True)
    mingw = shutil.which('x86_64-w64-mingw32-g++')
    if not mingw:
        raise SystemExit('Missing x86_64-w64-mingw32-g++; install MinGW-w64 (brew install mingw-w64).')
    includes = ['-I' + str(cpp / x) for x in ['include', 'gen/include', 'gdextension']]
    subprocess.run([mingw, '-std=c++17', '-O2', '-ffp-contract=off', '-fvisibility=hidden', *prefix_maps, '-shared', *includes,
                    str(source / 'geometry_kernel.cpp'), str(library), '-static', '-static-libgcc', '-static-libstdc++',
                    '-s', '-Wl,--no-insert-timestamp', '-o', str(out / 'SCDDGeometry.windows.x86_64.dll')], check=True)

for notice in [source / 'GODOT-CPP-LICENSE.md', source.parents[1] / 'game/addons/scdd_geometry/GODOT-CPP-LICENSE.md']:
    shutil.copyfile(cpp / 'LICENSE.md', notice)
print('Built unsigned geometry-kernel libraries: ' + ', '.join(platforms) + '.')

#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Unsigned reproducible Apple CloudKit bridge and completely offline harness."""
import argparse
import pathlib
import plistlib
import shutil
import subprocess
import tempfile

REVISION = 'e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77'
p = argparse.ArgumentParser()
p.add_argument('--test-only', action='store_true')
p.add_argument('--godot-cpp', type=pathlib.Path)
p.add_argument('--scons')
a = p.parse_args()
s = pathlib.Path(__file__).resolve().parent
frameworks = ['-framework', 'Foundation', '-framework', 'CloudKit', '-framework', 'Security']
flags = ['-std=c++17', '-fobjc-arc', '-fvisibility=hidden', '-Werror',
         f'-ffile-prefix-map={s.parents[1]}=/scdd', f'-fdebug-prefix-map={s.parents[1]}=/scdd']
if a.test_only:
    # Excludes the actual factory implementation at compile time. No CKContainer.
    out = pathlib.Path(tempfile.mkdtemp(prefix='scdd-cloud-native-'))
    for arch in ('arm64', 'x86_64'):
        binary = out / arch
        subprocess.run(['xcrun', 'clang++', *flags, '-DSCDD_CLOUD_TEST_ONLY=1',
                        '-arch', arch, '-mmacosx-version-min=12.0',
                        str(s / 'cloud_transport.mm'), str(s / 'tests/cloud_transport_tests.mm'),
                        *frameworks, '-o', str(binary)], check=True)
        output = subprocess.check_output(['/usr/bin/arch', '-' + arch, str(binary)], text=True)
        print(arch + ': ' + output.strip(), flush=True)
        if ' passed, 0 failed' not in output:
            raise SystemExit('Native harness did not report a clean result')
    raise SystemExit(0)
if not a.godot_cpp or not a.scons:
    p.error('--godot-cpp and --scons are required for native library builds')
cpp = a.godot_cpp.resolve()
revision = subprocess.check_output(['git', '-C', str(cpp), 'rev-parse', 'HEAD'], text=True).strip()
if revision != REVISION:
    raise SystemExit('Use the documented pinned official godot-cpp revision')
out = s.parents[1] / 'game/addons/apple_cloud/bin'
out.mkdir(parents=True, exist_ok=True)
for platform, arch, sdk in [('macos', 'universal', 'macosx'), ('ios', 'arm64', 'iphoneos')]:
    # godot-cpp does not expose ccflags as a command-line option. Export an
    # explicit SCons environment so path maps reach every generated binding.
    wrapper = pathlib.Path(tempfile.mkdtemp(prefix='scdd-cloud-scons-')) / 'SConstruct'
    wrapper.write_text("env = Environment(tools=['default'], PLATFORM='')\n"
                       + "env.Append(CCFLAGS=" + repr([f'-ffile-prefix-map={cpp}=/godot-cpp', f'-fdebug-prefix-map={cpp}=/godot-cpp']) + ")\n"
                       + "env['ENV']['TMPDIR'] = '/private/tmp'\n"
                       + "SConscript(" + repr(str(cpp / 'SConstruct')) + ", exports={'env': env})\n")
    subprocess.run([a.scons, '-C', str(cpp), '-f', str(wrapper), f'platform={platform}', 'target=template_release',
                    f'arch={arch}', f'build_profile={s / "build_profile.json"}',
                    'debug_symbols=no', '-j4',
                    'ios_min_version=17.0' if platform == 'ios' else 'macos_deployment_target=12.0'], check=True)
    sdk_path = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
    library = cpp / 'bin' / f'libgodot-cpp.{platform}.template_release.{arch}.a'
    target = out / ('libSCDDAppleCloud.dylib' if platform == 'macos' else 'SCDDAppleCloud.framework/SCDDAppleCloud')
    target.parent.mkdir(parents=True, exist_ok=True)
    architectures = ['-arch', 'arm64', '-arch', 'x86_64'] if platform == 'macos' else ['-arch', 'arm64']
    install = '@rpath/libSCDDAppleCloud.dylib' if platform == 'macos' else '@rpath/SCDDAppleCloud.framework/SCDDAppleCloud'
    subprocess.run(['xcrun', '--sdk', sdk, 'clang++', *flags,
                    f'-ffile-prefix-map={cpp}=/godot-cpp', f'-fdebug-prefix-map={cpp}=/godot-cpp', '-O2', '-dynamiclib', *architectures,
                    '-isysroot', sdk_path, *['-I' + str(cpp / x) for x in ['include', 'gen/include', 'gdextension']],
                    str(s / 'cloud_transport.mm'), str(s / 'apple_cloud.mm'), str(library),
                    *frameworks, '-mmacosx-version-min=12.0' if platform == 'macos' else '-miphoneos-version-min=17.0',
                    '-Wl,-install_name,' + install, '-o', str(target)], check=True)
    if platform == 'ios':
        with (target.parent / 'Info.plist').open('wb') as f:
            plistlib.dump({'CFBundleExecutable': 'SCDDAppleCloud',
                          'CFBundleIdentifier': 'com.sierraburkhart.sincitydesertdreams.cloud',
                          'CFBundleName': 'SCDDAppleCloud', 'CFBundlePackageType': 'FMWK',
                          'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '1',
                          'MinimumOSVersion': '17.0', 'CFBundleSupportedPlatforms': ['iPhoneOS']}, f)
for destination in [s / 'GODOT-CPP-LICENSE.md', out.parent / 'GODOT-CPP-LICENSE.md']:
    shutil.copyfile(cpp / 'LICENSE.md', destination)
print('Built unsigned macOS universal (12.0) and iOS arm64 (17.0) libraries.')

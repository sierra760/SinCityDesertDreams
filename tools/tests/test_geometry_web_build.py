# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
"""Exercise the Web build CLI at its external compiler/process boundary."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
REVISION = 'e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77'


class WebGeometryBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='geometry-web-build-')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.repo = self.base / 'source with spaces'
        self.source = self.repo / 'native/geometry-kernel'
        self.source.mkdir(parents=True)
        shutil.copyfile(ROOT / 'native/geometry-kernel/build.py', self.source / 'build.py')
        (self.source / 'geometry_kernel.cpp').write_text('// compiler boundary fixture\n')
        (self.repo / 'native/apple-share').mkdir()
        (self.repo / 'native/apple-share/build_profile.json').write_text('{"enabled_classes":["RefCounted","OS"]}')
        self.cpp = self.base / 'bindings with spaces'
        (self.cpp / 'bin').mkdir(parents=True)
        (self.cpp / 'LICENSE.md').write_text('Bindings license fixture\n')
        self.library = self.cpp / 'bin/libgodot-cpp.web.template_release.wasm32.nothreads.a'
        self.library.write_bytes(b'!<arch>\n')
        self.tools = self.base / 'tools'
        self.tools.mkdir()
        self.calls = self.base / 'calls.jsonl'
        self.env = dict(os.environ, PATH=str(self.tools), BUILD_CALLS=str(self.calls), FAKE_REVISION=REVISION)
        self.tool('git', 'print(os.environ["FAKE_REVISION"])\n')
        self.tool('em++', '''
if '--version' in sys.argv:
    print('emcc (Emscripten gcc/clang-like replacement) '+os.environ.get('EMSCRIPTEN_VERSION', '6.0.12'))
    sys.exit(0)
with open(os.environ['BUILD_CALLS'], 'a') as f: f.write(json.dumps(sys.argv)+'\\n')
output = pathlib.Path(sys.argv[sys.argv.index('-o')+1])
output.write_bytes(b'broken' if os.environ.get('BAD_WASM') else b'\\0asm\\x01\\0\\0\\0')
sys.exit(int(os.environ.get('COMPILER_EXIT', '0')))
''')
        self.scons = self.tool('scons', '''
with open(os.environ['BUILD_CALLS'], 'a') as f: f.write(json.dumps(sys.argv)+'\\n')
base = pathlib.Path(sys.argv[sys.argv.index('-C')+1])
(base/'bin/libgodot-cpp.web.template_release.wasm32.nothreads.a').write_bytes(b'!<arch>\\n')
''')
        self.out = self.repo / 'game/addons/scdd_geometry/bin'
        self.out.mkdir(parents=True)
        self.desktop = self.out / 'libSCDDGeometry.dylib'
        self.desktop.write_bytes(b'preserve existing native artifact')
        self.target = self.out / 'SCDDGeometry.web.nothreads.wasm'

    def tool(self, name, body):
        path = self.tools / name
        path.write_text('#!'+sys.executable+'\nimport os,sys,json,pathlib\n'+body)
        path.chmod(0o755)
        return path

    def run_build(self, *extra):
        return subprocess.run([sys.executable, str(self.source/'build.py'), '--godot-cpp', str(self.cpp), '--platform', 'web', *extra], env=self.env, capture_output=True, text=True)

    def commands(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_web_build_uses_side_module_abi_and_preserves_desktop_binary(self):
        result = self.run_build()
        self.assertEqual(0, result.returncode, result.stdout+result.stderr)
        self.assertEqual(b'\0asm\x01\0\0\0', self.target.read_bytes())
        command = self.commands()[-1]
        for flag in ['-ffp-contract=off', '-sSIDE_MODULE=1', '-sSUPPORT_LONGJMP=wasm']:
            self.assertIn(flag, command)
        # BigInt is always on from Emscripten 6; the setting is deprecated there.
        self.assertNotIn('-sWASM_BIGINT', command)
        self.assertIn(str(self.library.resolve()), command)
        self.assertFalse(any('PTHREAD' in arg or 'USE_PTHREADS' in arg for arg in command))
        self.assertEqual(b'preserve existing native artifact', self.desktop.read_bytes())

    def test_missing_bindings_builds_the_matching_single_thread_library(self):
        self.library.unlink()
        result = self.run_build('--scons', str(self.scons))
        self.assertEqual(0, result.returncode, result.stdout+result.stderr)
        command = self.commands()[0]
        for flag in ['platform=web', 'target=template_release', 'arch=wasm32', 'threads=no']:
            self.assertIn(flag, command)
        self.assertTrue(self.target.is_file())

    def test_failed_compiler_keeps_the_previous_web_artifact(self):
        self.target.write_bytes(b'previous reviewed wasm')
        self.env['COMPILER_EXIT'] = '1'
        result = self.run_build()
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(b'previous reviewed wasm', self.target.read_bytes())

    def test_invalid_compiler_output_is_not_published(self):
        self.target.write_bytes(b'previous reviewed wasm')
        self.env['BAD_WASM'] = '1'
        result = self.run_build()
        self.assertNotEqual(0, result.returncode)
        self.assertIn('WebAssembly', result.stdout+result.stderr)
        self.assertEqual(b'previous reviewed wasm', self.target.read_bytes())

    def test_rejects_bindings_from_an_unpinned_revision(self):
        self.env['FAKE_REVISION'] = '0'*40
        result = self.run_build()
        self.assertNotEqual(0, result.returncode)
        self.assertIn('documented official', result.stdout+result.stderr)
        self.assertFalse(self.calls.exists())

    def test_wrong_sdk_is_rejected_before_replacing_the_previous_artifact(self):
        self.target.write_bytes(b'previous reviewed wasm')
        self.env['EMSCRIPTEN_VERSION'] = '4.0.20'
        result = self.run_build()
        self.assertNotEqual(0, result.returncode)
        self.assertIn('6.0.12', result.stdout+result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertEqual(b'previous reviewed wasm', self.target.read_bytes())

    def test_missing_compiler_reports_setup_and_preserves_the_previous_artifact(self):
        self.target.write_bytes(b'previous reviewed wasm')
        (self.tools / 'em++').unlink()
        result = self.run_build()
        self.assertNotEqual(0, result.returncode)
        self.assertIn('Missing em++', result.stdout+result.stderr)
        self.assertEqual(b'previous reviewed wasm', self.target.read_bytes())


if __name__ == '__main__':
    unittest.main()

# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Private pre-signing template changes must be narrow, reproducible and bounded."""
import hashlib
import importlib.util
import json
from pathlib import Path
import stat
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import warnings

ROOT = Path(__file__).resolve().parents[2]
CLOUDKIT = '/System/Library/Frameworks/CloudKit.framework/Versions/A/CloudKit'
ENTRIES = ['macos_template.app/Contents/MacOS/godot_macos_' + kind + '.universal' for kind in ['debug', 'release']]


def dylib(name=CLOUDKIT, command=12):
    raw = name.encode() + b'\0'
    size = (24 + len(raw) + 7) & ~7
    return struct.pack('<6I', command, size, 24, 0, 0, 0) + raw + bytes(size - 24 - len(raw))


def thin(cpu, extra=b'', section_offset=1024):
    payload = b'UNMODIFIED SECTION BYTES' * 4
    size = section_offset + len(payload)
    seg = struct.pack('<II16sQQQQiiII', 0x19, 152, b'__TEXT', 0x100000000, size, 0, size, 7, 5, 1, 0)
    sec = struct.pack('<16s16sQQIIIIIIII', b'__text', b'__TEXT', 0x100000000 + section_offset, len(payload), section_offset, 0, 0, 0, 0, 0, 0, 0)
    commands = seg + sec + extra
    count = 1; pos = 0
    while pos < len(extra):
        count += 1; pos += struct.unpack_from('<I', extra, pos + 4)[0]
    head = struct.pack('<8I', 0xfeedfacf, cpu, 3 if cpu == 0x1000007 else 0, 2, count, len(commands), 0, 0)
    return head + commands + bytes(section_offset - len(head) - len(commands)) + payload


def universal(extras=(b'', b'')):
    bodies = [thin(cpu, extra) for cpu, extra in zip([0x1000007, 0x100000c], extras)]
    data = bytearray(12288)
    struct.pack_into('>II', data, 0, 0xcafebabe, 2)
    for i, body in enumerate(bodies):
        start = 4096 * (i + 1)
        struct.pack_into('>5I', data, 8 + i * 20, 0x1000007 if i == 0 else 0x100000c, 3 if i == 0 else 0, start, len(body), 12)
        data[start:start + len(body)] = body
    return bytes(data)


def archive(path, binary=None, extra=None):
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for name, value in [(x, binary or universal()) for x in ENTRIES] + [('macos_template.app/Contents/Info.plist', b'unchanged plist')]+list(extra or []):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0)); info.create_system = 3
            info.external_attr = (stat.S_IFREG | (0o755 if name in ENTRIES else 0o644)) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with warnings.catch_warnings():
                warnings.filterwarnings('ignore', message='Duplicate name:')
                z.writestr(info, value)


class TemplateTests(unittest.TestCase):
    def setUp(self):
        path = ROOT / 'tools/prepare_apple_cloud_macos_template.py'
        self.assertTrue(path.is_file(), 'Bounded private template preparation tool missing')
        spec = importlib.util.spec_from_file_location('macos_template', path)
        self.tool = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.tool)

    def test_append_preserves_sections_old_commands_ordinals_and_exact_diff(self):
        original = universal((dylib('/usr/lib/libSystem.B.dylib'), dylib('/usr/lib/libSystem.B.dylib')))
        changed, manifest = self.tool.patch_macos_main(original)
        self.assertEqual(len(original), len(changed))
        self.assertEqual({'arm64', 'x86_64'}, set(self.tool.inspect_macos_main(changed)))
        allowed = set()
        for arch in manifest:
            start = arch['slice_offset']; end = start + 32 + arch['old_sizeofcmds']
            self.assertEqual(original[start + 32:end], changed[start + 32:end])
            self.assertEqual(original[start + 1024:start + arch['slice_size']], changed[start + 1024:start + arch['slice_size']])
            self.assertEqual(arch['old_ncmds'] + 1, struct.unpack_from('<I', changed, start + 16)[0])
            allowed.update(range(start + 16, start + 24)); allowed.update(range(end, end + len(dylib())))
        differences = {i for i, pair in enumerate(zip(original, changed)) if pair[0] != pair[1]}
        self.assertTrue(differences); self.assertTrue(differences <= allowed)
        with self.assertRaises(ValueError): self.tool.patch_macos_main(changed)

    def test_main_inspection_requires_strong_exact_dependency_in_both_architectures(self):
        self.assertEqual({'arm64', 'x86_64'}, set(self.tool.inspect_macos_main(universal((dylib(), dylib())))))
        for extras in [(b'', b''), (dylib(), b''), (b'', dylib()), (dylib(command=0x80000018), dylib()), (dylib()+dylib(), dylib()), (dylib('@rpath/CloudKit.framework/CloudKit'), dylib())]:
            with self.subTest(extras=tuple(len(x) for x in extras)), self.assertRaises(ValueError): self.tool.inspect_macos_main(universal(extras))
        for extra in [dylib(), dylib(command=0x80000018), dylib('@rpath/CloudKit.framework/CloudKit')]:
            with self.assertRaises(ValueError): self.tool.patch_macos_main(universal((extra, b'')))

    def test_rejects_malformed_fat_headers_slices_commands_sections_and_padding(self):
        base = universal(); cases = []
        for offset, fmt, value in [(0, '>I', 0xcafebabf), (4, '>I', 3), (16, '>I', 0), (36, '>I', 4096), (24, '>I', 32), (28, '>I', 0x1000007), (4096+12, '<I', 6), (4096+16, '<I', 1000), (4096+20, '<I', 8), (4096+36, '<I', 0), (4096+32, '<I', 0x777), (4096+32+72+48, '<I', 180)]:
            value_bytes = bytearray(base); struct.pack_into(fmt, value_bytes, offset, value); cases.append(value_bytes)
        padding = bytearray(base);padding[4096+184] = 1;cases.append(padding)
        truncated = base[:8300];cases.append(truncated)
        for n, data in enumerate(cases):
            with self.subTest(case=n), self.assertRaises(ValueError): self.tool.patch_macos_main(bytes(data))
        no_room = bytearray(base);struct.pack_into('<I', no_room, 4096+32+72+48, 200)
        with self.assertRaises(ValueError):self.tool.patch_macos_main(bytes(no_room))

    def test_archive_is_deterministic_preserves_members_permissions_and_reports_hashes(self):
        with tempfile.TemporaryDirectory() as temp:
            t=Path(temp);source=t/'macos.zip';archive(source);digest=hashlib.sha256(source.read_bytes()).hexdigest()
            for i in [1,2]: self.tool.prepare(source, digest, t/f'prepared{i}.zip', t/f'manifest{i}.json')
            self.assertEqual((t/'prepared1.zip').read_bytes(),(t/'prepared2.zip').read_bytes())
            self.assertEqual((t/'manifest1.json').read_bytes(),(t/'manifest2.json').read_bytes())
            self.assertEqual(digest,hashlib.sha256(source.read_bytes()).hexdigest())
            report=json.loads((t/'manifest1.json').read_text());self.assertEqual(digest,report['input_sha256'])
            self.assertEqual(hashlib.sha256((t/'prepared1.zip').read_bytes()).hexdigest(), report['output_sha256'])
            with zipfile.ZipFile(source) as old,zipfile.ZipFile(t/'prepared1.zip') as new:
                self.assertEqual(old.namelist(),new.namelist())
                for info in old.infolist():
                    self.assertEqual(info.external_attr,new.getinfo(info.filename).external_attr)
                    if info.filename not in ENTRIES:self.assertEqual(old.read(info),new.read(info.filename))
                    else:self.tool.inspect_macos_main(new.read(info.filename))

    def test_archive_refuses_wrong_digest_alias_overwrite_and_signing_inputs(self):
        with tempfile.TemporaryDirectory() as temp:
            t=Path(temp);source=t/'macos.zip';archive(source);digest=hashlib.sha256(source.read_bytes()).hexdigest()
            for args in [(source,'0'*64,t/'out',t/'manifest'),(source,digest,source,t/'manifest'),(source,digest,t/'out',source),(source,digest,t/'out',t/'out')]:
                with self.assertRaises(ValueError):self.tool.prepare(*args)
            (t/'out').write_bytes(b'keep')
            with self.assertRaises(ValueError):self.tool.prepare(source,digest,t/'out',t/'manifest')
            self.assertEqual(b'keep',(t/'out').read_bytes());(t/'out').unlink()
            for name in ['../outside','/absolute','macos_template.app/../outside','macos_template.app\\bad','macos_template.app/secret.p12','macos_template.app/embedded.provisionprofile','macos_template.app/test.entitlements',ENTRIES[0]]:
                with self.subTest(name=name):
                    archive(source,extra=[(name,b'private')]);digest=hashlib.sha256(source.read_bytes()).hexdigest()
                    with self.assertRaises(ValueError):self.tool.prepare(source,digest,t/'out',t/'manifest')
                    self.assertFalse((t/'out').exists());self.assertFalse((t/'manifest').exists())

    def test_archive_limits_symlinks_and_missing_entries_fail_before_publication(self):
        with tempfile.TemporaryDirectory() as temp:
            t=Path(temp);source=t/'macos.zip';archive(source)
            def attempt():self.tool.prepare(source,hashlib.sha256(source.read_bytes()).hexdigest(),t/'out',t/'manifest')
            for limit in ['MAX_ZIP_BYTES','MAX_ENTRY_BYTES','MAX_TOTAL_BYTES','MAX_ENTRIES']:
                with self.subTest(limit=limit),patch.object(self.tool,limit,1),self.assertRaises(ValueError):attempt()
            with zipfile.ZipFile(source,'w') as z:
                i=zipfile.ZipInfo(ENTRIES[0]);i.create_system=3;i.external_attr=(stat.S_IFLNK|0o777)<<16;z.writestr(i,b'/elsewhere')
            with self.assertRaises(ValueError):attempt()
            with zipfile.ZipFile(source,'w') as z:z.writestr('macos_template.app/Contents/Info.plist',b'only')
            with self.assertRaises(ValueError):attempt()
            self.assertFalse((t/'out').exists())

    def test_zip_header_flags_crc_truncation_and_overlap_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            t=Path(temp);source=t/'macos.zip';archive(source);original=source.read_bytes()
            central=original.index(b'PK\x01\x02')
            cases=[]
            for offset, fmt, value in [(6,'<H',1),(central+8,'<H',1),(central+16,'<I',0),(central+42,'<I',1)]:
                data=bytearray(original);struct.pack_into(fmt,data,offset,value);cases.append(bytes(data))
            cases.append(original[:-15])
            for n,data in enumerate(cases):
                with self.subTest(case=n):
                    source.write_bytes(data)
                    with self.assertRaises(ValueError):self.tool.prepare(source,hashlib.sha256(data).hexdigest(),t/'out',t/'manifest')
                    self.assertFalse((t/'out').exists());self.assertFalse((t/'manifest').exists())

    def test_data_commands_cannot_claim_zero_header_padding(self):
        # LC_FUNCTION_STARTS points into otherwise zero bytes after load commands.
        command=struct.pack('<4I',0x26,16,216,8)
        data=universal((command,b''))
        with self.assertRaises(ValueError):self.tool.patch_macos_main(data)

    def test_publication_never_overwrites_a_racing_manifest_writer(self):
        with tempfile.TemporaryDirectory() as temp:
            t=Path(temp);source=t/'macos.zip';archive(source)
            original_link=self.tool.os.link
            def race(src,dst):
                original_link(src,dst)
                (t/'manifest').write_bytes(b'other writer')
            with patch.object(self.tool.os,'link',side_effect=race),self.assertRaises(ValueError):
                self.tool.prepare(source,hashlib.sha256(source.read_bytes()).hexdigest(),t/'out',t/'manifest')
            self.assertEqual(b'other writer',(t/'manifest').read_bytes());self.assertFalse((t/'out').exists())

    def test_zip_entry_count_is_bounded_before_central_directory_allocation(self):
        with tempfile.TemporaryDirectory() as temp:
            t=Path(temp);source=t/'macos.zip';archive(source);data=bytearray(source.read_bytes())
            end=data.rindex(b'PK\x05\x06');struct.pack_into('<HH',data,end+8,129,129);source.write_bytes(data)
            with patch.object(self.tool.zipfile,'ZipFile',side_effect=AssertionError('directory allocated before count guard')):
                with self.assertRaises(ValueError):
                    self.tool.prepare(source,hashlib.sha256(data).hexdigest(),t/'out',t/'manifest')

if __name__ == '__main__':unittest.main()

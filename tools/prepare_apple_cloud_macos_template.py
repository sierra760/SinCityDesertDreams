#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare a private Godot 4.7.2 macOS ZIP before normal export/signing.

Never launch the intermediate executables: their old signatures are stale.
No installed template, project setting, entitlement or signing identity is edited.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import tempfile
import zipfile

CLOUDKIT = '/System/Library/Frameworks/CloudKit.framework/Versions/A/CloudKit'
EXECUTABLES = tuple('macos_template.app/Contents/MacOS/godot_macos_' + kind + '.universal' for kind in ('debug', 'release'))
MAX_ZIP_BYTES = 256 * 1024 * 1024
MAX_ENTRY_BYTES = 256 * 1024 * 1024
MAX_TOTAL_BYTES = 512 * 1024 * 1024
MAX_ENTRIES = 128
MAX_COMMAND_BYTES = 65536
ARCHES = {0x01000007: ('x86_64', 3), 0x0100000c: ('arm64', 0)}
DYLIB_COMMANDS = {0xc, 0x80000018, 0x8000001f, 0x20, 0x80000023}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def _cstring(command, offset):
    require(0 <= offset < len(command), 'Invalid load-command string offset')
    end = command.find(b'\0', offset)
    require(end >= 0, 'Unterminated load-command string')
    try:
        return command[offset:end].decode('utf-8')
    except UnicodeDecodeError as error:
        raise ValueError('Invalid load-command string encoding') from error


def _slices(data):
    require(48 <= len(data) <= MAX_ENTRY_BYTES, 'Invalid bounded main executable size')
    require(struct.unpack_from('>II', data) == (0xcafebabe, 2), 'Expected two-slice FAT32 universal executable')
    result = []; seen = set()
    for i in range(2):
        cpu, subtype, offset, size, align = struct.unpack_from('>5I', data, 8 + i * 20)
        require(cpu in ARCHES and cpu not in seen and subtype == ARCHES[cpu][1], 'Unexpected/duplicate architecture or subtype')
        require(0 <= align <= 20 and offset >= 48 and offset % (1 << align) == 0, 'Invalid FAT alignment/header overlap')
        require(size >= 32 and offset + size <= len(data), 'Truncated FAT slice')
        seen.add(cpu); result.append((cpu, subtype, offset, size))
    ordered = sorted(result, key=lambda x: x[2])
    require(ordered[0][2] + ordered[0][3] <= ordered[1][2], 'Overlapping FAT slices')
    return result


def _inspect(data):
    """Parse only known 64-bit executable layouts; every file-backed range is bounded.

    Returned header space ends at the earliest section or load-command data.
    Zero bytes alone never establish unused padding.
    """
    result = []
    for cpu, subtype, start, size in _slices(data):
        image = memoryview(data)[start:start + size]
        magic, actual_cpu, actual_sub, filetype, count, command_size, flags, reserved = struct.unpack_from('<8I', image)
        require((magic, actual_cpu, actual_sub, filetype, reserved) == (0xfeedfacf, cpu, subtype, 2, 0), 'Expected matching little-endian MH_EXECUTE slice')
        require(1 <= count <= 512 and count * 8 <= command_size <= MAX_COMMAND_BYTES and 32 + command_size <= size, 'Invalid load-command bounds')
        end = 32 + command_size; position = 32
        segments = []; sections = []; occupied = []; libraries = []; text_segments = []

        def payload(offset, length):
            if not length:
                require(0 <= offset <= size, 'Invalid empty data offset')
                return
            require(end <= offset and length <= size - offset, 'Load-command data overlaps header or exceeds slice')
            occupied.append((offset, offset + length))

        for _ in range(count):
            require(position + 8 <= end, 'Truncated load command')
            cmd, length = struct.unpack_from('<II', image, position)
            require(length >= 8 and length % 8 == 0 and position + length <= end, 'Invalid load-command size/alignment')
            command = bytes(image[position:position + length])
            if cmd == 0x19:  # LC_SEGMENT_64
                require(length >= 72, 'Truncated segment')
                _, _, name, vmaddr, vmsize, offset, file_size, maxprot, initprot, nsects, segflags = struct.unpack_from('<II16sQQQQiiII', command)
                require(nsects <= 128 and length == 72 + nsects * 80, 'Invalid section table')
                require(offset <= size and file_size <= size - offset and file_size <= vmsize, 'Invalid segment file bounds')
                if file_size:
                    require(offset == 0 or offset >= end, 'Segment overlaps load commands')
                    segments.append((offset, offset + file_size))
                if name.rstrip(b'\0') == b'__TEXT':
                    require(offset == 0 and file_size >= end and nsects > 0, 'Unexpected __TEXT header layout')
                    text_segments.append((vmaddr, file_size))
                for j in range(nsects):
                    sec = struct.unpack_from('<16s16sQQIIIIIIII', command, 72 + j * 80)
                    _, segname, addr, amount, sec_offset, alignment, reloc, nreloc, secflags, _, _, _ = sec
                    require(segname == name and alignment <= 31 and vmaddr <= addr and amount <= vmaddr + vmsize - addr, 'Invalid section VM bounds')
                    if secflags & 0xff not in (1, 0xc, 0x12):  # zero-fill sections have no file bytes
                        require(offset <= sec_offset and amount <= offset + file_size - sec_offset, 'Section outside segment')
                        require(addr - vmaddr == sec_offset - offset, 'Section VM/file mapping disagrees')
                        payload(sec_offset, amount)
                        if amount: sections.append((sec_offset, sec_offset + amount))
                    payload(reloc, nreloc * 8)
            elif cmd in DYLIB_COMMANDS:
                require(length >= 24, 'Truncated dylib command')
                name_offset = struct.unpack_from('<I', command, 8)[0]
                require(name_offset >= 24, 'Dylib string overlaps command fields')
                libraries.append((cmd, _cstring(command, name_offset)))
            elif cmd == 0x80000022:  # LC_DYLD_INFO_ONLY
                require(length == 48, 'Invalid dyld info')
                values = struct.unpack_from('<10I', command, 8)
                for j in range(0, 10, 2): payload(values[j], values[j + 1])
            elif cmd == 0x2:  # LC_SYMTAB, nlist_64
                require(length == 24, 'Invalid symtab')
                sym, nsyms, strings, string_size = struct.unpack_from('<4I', command, 8)
                payload(sym, nsyms * 16); payload(strings, string_size)
            elif cmd == 0xb:  # LC_DYSYMTAB: the last six pairs reference file tables.
                require(length == 80, 'Invalid dysymtab')
                values = struct.unpack_from('<18I', command, 8)
                for j, unit in zip(range(6, 18, 2), (8, 56, 4, 4, 8, 8)): payload(values[j], values[j + 1] * unit)
            elif cmd in (0x1d, 0x1e, 0x26, 0x29, 0x2e, 0x80000033, 0x80000034):
                require(length == 16, 'Invalid linkedit data command')
                payload(*struct.unpack_from('<II', command, 8))
            elif cmd == 0x80000028:  # LC_MAIN entry point is a file offset.
                require(length == 24, 'Invalid entry point command')
                entry = struct.unpack_from('<Q', command, 8)[0]; payload(entry, 1)
            elif cmd in (0xe, 0x8000001c):  # dylinker / rpath, no file data.
                require(length >= 16, 'Truncated path command')
                string_offset = struct.unpack_from('<I', command, 8)[0]
                require(string_offset >= 12, 'Invalid path string offset'); _cstring(command, string_offset)
            elif cmd in (0x1b, 0x24, 0x2a):
                require(length == {0x1b: 24, 0x24: 16, 0x2a: 16}[cmd], 'Invalid fixed load command')
            elif cmd == 0x32:
                require(length >= 24, 'Truncated build version')
                ntools = struct.unpack_from('<I', command, 20)[0]
                require(ntools <= 32 and length == 24 + ntools * 8, 'Invalid build version tools')
            else:
                raise ValueError(f'Unsupported load command {cmd:#x}')
            position += length
        require(position == end, 'Load-command count/size mismatch')
        require(len(text_segments) == 1 and sections, 'Missing unique __TEXT and file sections')
        for ranges, label in [(segments, 'segments'), (sections, 'sections')]:
            ordered = sorted(ranges)
            require(all(a[1] <= z[0] for a, z in zip(ordered, ordered[1:])), 'Overlapping ' + label)
        first_data = min(x[0] for x in occupied)
        require(first_data <= text_segments[0][1], 'No data bounds for header padding')
        cloud = [(cmd, name) for cmd, name in libraries if 'cloudkit' in name.lower()]
        result.append(dict(architecture=ARCHES[cpu][0], slice_offset=start, slice_size=size,
                           old_ncmds=count, old_sizeofcmds=command_size, first_data_offset=first_data,
                           cloudkit=cloud))
    return result


def inspect_macos_main(data):
    """Require a direct strong CloudKit dependency independently in both slices."""
    slices = _inspect(data)
    for item in slices:
        require(item['cloudkit'] == [(0xc, CLOUDKIT)], item['architecture'] + ': missing, weak or ambiguous main CloudKit dependency')
    return [item['architecture'] for item in slices]


def patch_macos_main(data):
    slices = _inspect(data); changed = bytearray(data); report = []
    raw = CLOUDKIT.encode() + b'\0'; length = (24 + len(raw) + 7) & ~7
    command = struct.pack('<6I', 0xc, length, 24, 0, 0, 0) + raw + bytes(length - 24 - len(raw))
    for item in slices:
        require(not item['cloudkit'], 'Template already has a strong, weak or ambiguous CloudKit dependency')
        start = item['slice_offset']; end = start + 32 + item['old_sizeofcmds']
        require(end + length <= start + item['first_data_offset'], 'Insufficient unused header padding')
        require(not any(data[end:end + length]), 'Header padding is not zero')
        before = bytes(changed[start + 16:start + 24])
        struct.pack_into('<II', changed, start + 16, item['old_ncmds'] + 1, item['old_sizeofcmds'] + length)
        changed[end:end + length] = command
        entry = {key: value for key, value in item.items() if key != 'cloudkit'}
        entry['changes'] = [dict(offset=start + 16, before_hex=before.hex(), after_hex=bytes(changed[start + 16:start + 24]).hex()),
                            dict(offset=end, before_hex=data[end:end + length].hex(), after_hex=command.hex())]
        report.append(entry)
    result = bytes(changed); inspect_macos_main(result)
    return result, report


def _zip_entries(z, archive_size):
    infos = z.infolist(); require(1 <= len(infos) <= MAX_ENTRIES, 'Unbounded ZIP entry count')
    names = set(); total = 0; ranges = []
    require(0 <= z.start_dir <= archive_size, 'Invalid ZIP directory')
    for info in infos:
        name = info.filename; parts = PurePosixPath(name).parts
        require(name == info.orig_filename and name and '\\' not in name and '\0' not in name and ':' not in name and not name.startswith('/') and
                all(x not in ('', '.', '..') for x in name.rstrip('/').split('/')) and
                parts[0] == 'macos_template.app', 'Unsafe ZIP member path')
        folded = name.rstrip('/').casefold(); require(folded not in names, 'Duplicate ZIP member'); names.add(folded)
        mode = info.external_attr >> 16
        require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR), 'Non-regular ZIP member (links unsupported)')
        require(stat.S_IFMT(mode) in (0, stat.S_IFDIR if info.is_dir() else stat.S_IFREG), 'ZIP member type/path disagree')
        require(not info.flag_bits & ~0x806 and info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), 'Encrypted/unsupported ZIP member')
        require(0 <= info.file_size <= MAX_ENTRY_BYTES and 0 <= info.compress_size <= MAX_ZIP_BYTES, 'Unbounded ZIP member')
        require(not info.is_dir() or info.file_size == 0, 'Directory carries data')
        require(not name.lower().endswith(('.p12', '.pfx', '.pem', '.cer', '.crt', '.der', '.key', '.mobileprovision', '.provisionprofile', '.entitlements')), 'Signing input in template')
        total += info.file_size; require(total <= MAX_TOTAL_BYTES, 'Unbounded ZIP expanded total')
        z.fp.seek(info.header_offset); local = z.fp.read(30)
        require(len(local) == 30 and local[:4] == b'PK\x03\x04', 'Invalid ZIP local header')
        fields = struct.unpack('<4s5H3I2H', local)
        require(fields[2] == info.flag_bits and fields[3] == info.compress_type, 'ZIP header flags disagree')
        data_start = info.header_offset + 30 + fields[-2] + fields[-1]
        require(info.header_offset >= 0 and data_start + info.compress_size <= z.start_dir, 'ZIP payload overlaps directory')
        ranges.append((info.header_offset, data_start + info.compress_size))
    ordered = sorted(ranges)
    require(all(a[1] <= z[0] for a, z in zip(ordered, ordered[1:])), 'Overlapping ZIP entries')
    require(all(name in z.namelist() for name in EXECUTABLES), 'Missing debug/release universal template')
    for name in EXECUTABLES:
        require((z.getinfo(name).external_attr >> 16) & 0o111, 'Main template lacks executable permissions')
    return infos


def _zip_directory_bound(raw):
    # Validate the small directory before ZipFile allocates any per-entry objects.
    end = raw.rfind(b'PK\x05\x06', max(0, len(raw) - 65557))
    require(end >= 0 and end + 22 <= len(raw), 'Missing ZIP end record')
    _, disk, central_disk, disk_count, count, amount, offset, comment = struct.unpack_from('<4s4H2IH', raw, end)
    require(disk == central_disk == 0 and disk_count == count and 1 <= count <= MAX_ENTRIES,
            'Multi-disk/ZIP64 or unbounded ZIP entry count')
    require(end + 22 + comment == len(raw) and amount <= MAX_ENTRIES * 8192 and offset + amount == end,
            'Invalid or unbounded ZIP central directory')
    position = offset
    for _ in range(count):
        require(position + 46 <= end and raw[position:position + 4] == b'PK\x01\x02', 'Truncated ZIP directory entry')
        require(struct.unpack_from('<H', raw, position + 6)[0] <= 20 and struct.unpack_from('<H', raw, position + 34)[0] == 0,
                'Unsupported ZIP version or disk')
        name, extra, note = struct.unpack_from('<3H', raw, position + 28)
        length = 46 + name + extra + note
        require(1 <= name <= 1024 and length <= 8192 and position + length <= end, 'Unbounded ZIP directory fields')
        position += length
    require(position == end, 'ZIP directory count/length mismatch')


def prepare(source, expected_sha256, output, manifest):
    source, output, manifest = map(Path, (source, output, manifest))
    require(re.fullmatch('[0-9a-fA-F]{64}', expected_sha256) is not None, 'Explicit input SHA-256 required')
    require(len({p.resolve() for p in (source, output, manifest)}) == 3, 'Input/output/manifest must be separate paths')
    require(not output.exists() and not output.is_symlink() and not manifest.exists() and not manifest.is_symlink(), 'Output/manifest already exists')
    require(source.is_file() and source.stat().st_size <= MAX_ZIP_BYTES, 'Input ZIP exceeds bound or is missing')
    # One bounded snapshot binds validation and transformation, even if source changes later.
    with source.open('rb') as stream: raw = stream.read(MAX_ZIP_BYTES + 1)
    require(len(raw) <= MAX_ZIP_BYTES and digest(raw) == expected_sha256.lower(), 'Input ZIP SHA-256 mismatch')
    _zip_directory_bound(raw)
    import io
    report = dict(format_version=1, tool='prepare_apple_cloud_macos_template', input_sha256=digest(raw),
                  warning='Intermediate executable signatures are stale; never launch. Godot must sign the final export.', entries=[])
    output.parent.mkdir(parents=True, exist_ok=True); manifest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.cloud-template-', dir=output.parent) as temporary:
        zip_path = Path(temporary) / 'prepared.zip'
        try:
            with zipfile.ZipFile(io.BytesIO(raw)) as old:
                infos = _zip_entries(old, len(raw))
                with zipfile.ZipFile(zip_path, 'w', allowZip64=False, compression=zipfile.ZIP_DEFLATED, compresslevel=9) as new:
                    new.comment = old.comment
                    for info in infos:
                        with old.open(info) as stream: data = stream.read(info.file_size + 1)
                        require(len(data) == info.file_size, 'ZIP member size mismatch')
                        before = digest(data); changes = []
                        if info.filename in EXECUTABLES: data, changes = patch_macos_main(data)
                        new.writestr(copy.copy(info), data)
                        report['entries'].append(dict(name=info.filename, size=len(data), external_attr=info.external_attr,
                                                      before_sha256=before, after_sha256=digest(data), slices=changes))
            require(zip_path.stat().st_size <= MAX_ZIP_BYTES, 'Output ZIP exceeds bound')
            report['output_sha256'] = digest(zip_path.read_bytes())
            # Stage both files before exclusive publication; never replace a racing writer.
            with tempfile.TemporaryDirectory(prefix='.cloud-manifest-', dir=manifest.parent) as manifest_temp:
                manifest_path = Path(manifest_temp) / 'manifest.json'
                manifest_path.write_text(json.dumps(report, sort_keys=True, indent=2) + '\n')
                os.link(zip_path, output)
                try:
                    os.link(manifest_path, manifest)
                except BaseException:
                    # Remove only our own linked output, not a concurrent replacement.
                    try:
                        if output.samefile(zip_path): output.unlink()
                    except FileNotFoundError:
                        pass
                    raise
        except (zipfile.BadZipFile, RuntimeError, OSError, struct.error) as error:
            raise ValueError('Template preparation failed: ' + str(error)) from error
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--input-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--manifest', required=True, type=Path)
    args = parser.parse_args()
    try:
        prepare(args.input, args.input_sha256, args.output, args.manifest)
    except ValueError as error:
        parser.exit(1, f'FAIL: {error}\n')
    print('Prepared private template; signatures are stale. Export and sign with Godot before use.')


if __name__ == '__main__':
    main()

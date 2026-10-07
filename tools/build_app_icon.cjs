#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

/* Build the platform icon files from the project's vector master.
 * Usage: node tools/build_app_icon.cjs [--sharp-module /path/to/sharp] [--native-iconutil]
 * Uses Sharp (SVG rasterization), with an optional macOS iconutil re-encoding step.
 * It only writes icon files; it never exports the game or edits export presets.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const os = require('node:os');
const { execFileSync } = require('node:child_process');
const args = process.argv.slice(2);
const moduleIndex = args.indexOf('--sharp-module');
const sharp = require(moduleIndex >= 0 ? args[moduleIndex + 1] : 'sharp');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'assets/branding/app-icon/source');
const ui = path.join(root, 'game/assets/ui');
const output = path.join(ui, 'app-icon');
const svg = fs.readFileSync(path.join(source, 'master.svg'), 'utf8');
const foreground = fs.readFileSync(path.join(source, 'layers/foreground-combined.svg'), 'utf8');
const body = foreground.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '');
const wrapper = inner => '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">' + inner + '</svg>';
const outputs = [];
function write(relative, bytes) {
  const destination = path.join(output, relative);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, bytes);
  outputs.push(relative);
}
async function render(art, size, opaque = false) {
  let image = sharp(Buffer.from(art), { density: 96 }).resize(size, size).toColourspace('srgb');
  if (opaque) image = image.removeAlpha();
  return image.png().toBuffer();
}
function ico(images) {
  const header = Buffer.alloc(6 + images.length * 16);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(images.length, 4);
  let offset = header.length;
  for (let i = 0; i < images.length; i++) {
    const { size, png } = images[i];
    const at = 6 + i * 16;
    header[at] = header[at + 1] = size === 256 ? 0 : size;
    header.writeUInt16LE(1, at + 4);
    header.writeUInt16LE(32, at + 6);
    header.writeUInt32LE(png.length, at + 8);
    header.writeUInt32LE(offset, at + 12);
    offset += png.length;
  }
  return Buffer.concat([header, ...images.map(image => image.png)]);
}
function icns(chunks) {
  const parts = chunks.map(({ type, png }) => {
    const header = Buffer.alloc(8);
    header.write(type, 0, 4, 'ascii');
    header.writeUInt32BE(png.length + 8, 4);
    return Buffer.concat([header, png]);
  });
  const header = Buffer.alloc(8);
  header.write('icns', 0, 4, 'ascii');
  header.writeUInt32BE(parts.reduce((sum, part) => sum + part.length, 8), 4);
  return Buffer.concat([header, ...parts]);
}
async function main() {
  fs.mkdirSync(output, { recursive: true });
  fs.writeFileSync(path.join(ui, 'app_icon.svg'), svg);
  write('master.png', fs.readFileSync(path.join(source, 'approved-master.png')));
  const dark = svg.replace('fill="#075A63"', 'fill="#092B30"');
  write('apple/dark-1024.png', await render(dark, 1024, true));
  write('apple/tinted-1024.png', await sharp(path.join(output, 'master.png'))
    .greyscale().removeAlpha().png().toBuffer());
  for (const layer of ['01-sun', '02-googie-city', '03-atomic-sparkle']) {
    write('apple/layers/' + layer + '.svg', fs.readFileSync(path.join(source, 'layers', layer + '.svg')));
  }
  write('apple/background.svg', wrapper('<rect width="1024" height="1024" fill="#075A63"/>'));
  // Masking belongs only to the classic native container, never the Apple source layers.
  const rounded = wrapper('<defs><clipPath id="tile"><rect width="1024" height="1024" rx="230"/></clipPath></defs><g clip-path="url(#tile)">' +
    svg.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '') + '</g>');
  const mac = wrapper('<g transform="translate(100 100) scale(.8046875)">' +
    rounded.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '') + '</g>');
  write('desktop/macos-1024.png', await render(mac, 1024));
  const windowsImages = [];
  for (const size of [16, 24, 32, 48, 64, 128, 256]) windowsImages.push({ size, png: await render(rounded, size) });
  write('desktop/windows.ico', ico(windowsImages));
  const chunks = [];
  for (const [type, size] of [['icp4',16],['icp5',32],['icp6',64],['ic07',128],['ic08',256],['ic09',512],['ic10',1024],['ic11',32],['ic12',64],['ic13',256],['ic14',512]]) {
    chunks.push({ type, png: await render(mac, size) });
  }
  // PNG-bearing ICNS chunks keep this generator usable on any host.
  write('desktop/macos.icns', icns(chunks));
  if (process.platform === 'darwin' && args.includes('--native-iconutil')) {
    const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'sincity-app-icon-'));
    try {
      const iconset = path.join(temporary, 'Approved.iconset');
      fs.mkdirSync(iconset);
      for (const size of [16,32,128,256,512]) for (const scale of [1,2]) {
        fs.writeFileSync(path.join(iconset, 'icon_' + size + 'x' + size + (scale === 2 ? '@2x' : '') + '.png'),
          await render(mac, size * scale));
      }
      execFileSync('/usr/bin/iconutil', ['-c', 'icns', iconset, '-o', path.join(temporary, 'Approved.icns')]);
      write('desktop/macos.icns', fs.readFileSync(path.join(temporary, 'Approved.icns')));
    } finally { fs.rmSync(temporary, { recursive: true, force: true }); }
  }
  // Keep every foreground pixel inside Android's central 66dp-diameter circle.
  const androidTransform = 'translate(128 128) scale(.75)';
  const androidForeground = wrapper('<g transform="' + androidTransform + '">' + body + '</g>');
  write('android/foreground-432.png', await render(androidForeground, 432));
  write('android/background-432.png', await render(wrapper('<rect width="1024" height="1024" fill="#075A63"/>'), 432, true));
  write('android/legacy-192.png', await render(svg, 192, true));
  const monoBody = body.replace(/fill="#[0-9A-Fa-f]{6}"/g, match => match.includes('064852') ? 'fill="black"' : 'fill="white"');
  const mono = wrapper('<defs><mask id="symbol"><rect width="1024" height="1024" fill="black"/><g transform="' + androidTransform + '">' +
    monoBody + '</g></mask></defs><rect width="1024" height="1024" fill="white" mask="url(#symbol)"/>');
  write('android/monochrome-432.png', await render(mono, 432));
  write('web/favicon.ico', ico(windowsImages.filter(image => image.size <= 64)));
  for (const size of [32,180,192,512]) write('web/icon-' + size + '.png', await render(svg, size, true));
  const files = [];
  for (const relative of [...new Set(outputs)].sort()) {
    const bytes = fs.readFileSync(path.join(output, relative));
    const record = { file: relative, bytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex') };
    if (relative.endsWith('.png')) {
      const meta = await sharp(bytes).metadata();
      Object.assign(record, { width: meta.width, height: meta.height, space: meta.space, has_alpha: meta.hasAlpha });
    }
    files.push(record);
  }
  const manifest = {
    title: 'Sin City: Desert Dreams — Googie app icon',
    approved_date: '2026-10-05',
    source: 'assets/branding/app-icon/source/master.svg',
    generator: 'tools/build_app_icon.cjs',
    provenance: 'Project-authored vector geometry, refined from a concept sketch. No third-party image or logo references.',
    apple_native_layers: 'Unmasked vector layers, kept for future Icon Composer use.',
    files
  };
  fs.writeFileSync(path.join(output, 'provenance.json'), JSON.stringify(manifest, null, 2) + '\n');
  console.log(JSON.stringify({ generated: files.length, output: path.relative(root, output), master_preserved: true }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });

// Geometric app icon, rendered locally without third-party assets.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
const side = 1024;
const raw = Buffer.alloc((side * 3 + 1) * side);
for (let y = 0; y < side; y++) {
  for (let x = 0; x < side; x++) {
    const dx = x - 512, dy = y - 512;
    const distance = Math.hypot(dx, dy);
    const angle = (Math.atan2(dy, dx) + Math.PI * 2.5) % (Math.PI * 2);
    const t = (x + y) / (side * 2);
    let rgb = [235 - 85 * t, 6, 116 - 23 * t];
    const ring = Math.max(0, Math.min(1, 27 - Math.abs(distance - 300)));
    const opacity = ring * (angle < Math.PI * 1.57 ? 1 : 0.22);
    rgb = rgb.map(v => v * (1 - opacity) + 255 * opacity);
    const bars = [[394, 500, 60, 145], [484, 410, 60, 235], [574, 335, 60, 310]];
    if (bars.some(([bx, by, bw, bh]) => {
      const cx = Math.max(bx + 15, Math.min(x, bx + bw - 15));
      const cy = Math.max(by + 15, Math.min(y, by + bh - 15));
      return Math.hypot(x - cx, y - cy) <= 15;
    })) rgb = [255, 255, 255];
    const offset = y * (side * 3 + 1) + 1 + x * 3;
    rgb.forEach((v, i) => { raw[offset + i] = Math.round(v); });
  }
}
const crc = buf => {
  let c = 0xffffffff;
  for (const b of buf) { c ^= b; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; }
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (name, data) => {
  const tag = Buffer.from(name), head = Buffer.alloc(4), tail = Buffer.alloc(4);
  head.writeUInt32BE(data.length); tail.writeUInt32BE(crc(Buffer.concat([tag, data])));
  return Buffer.concat([head, tag, data, tail]);
};
const header = Buffer.alloc(13); header.writeUInt32BE(side, 0); header.writeUInt32BE(side, 4); header[8] = 8; header[9] = 2;
const png = Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
fs.writeFileSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../Assets.xcassets/AppIcon.appiconset/AppIcon.png'), png);
console.log('Generated opaque 1024px RGB app icon.');

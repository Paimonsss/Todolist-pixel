// Membuat ikon PWA pixel-art (papan tugas dengan centang) tanpa dependensi.
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';

const ART = [
  '................',
  '................',
  '.....NNNNNN.....',
  '..NNNNYYYYNNNN..',
  '..NWWNNNNNNWWN..',
  '..NWWWWWWWWWWN..',
  '..NWWWWWWWGGWN..',
  '..NWWWWWWGGGWN..',
  '..NWGGWWGGGWWN..',
  '..NWGGGGGGWWWN..',
  '..NWWGGGGWWWWN..',
  '..NWWWGGWWWWWN..',
  '..NWWWWWWWWWWN..',
  '..NNNNNNNNNNNN..',
  '...LLLLLLLLLLLL.',
  '................',
];
const COLORS = { '.': [185, 176, 255], N: [29, 26, 74], W: [255, 251, 240], Y: [255, 209, 102], G: [46, 196, 130], L: [124, 110, 230] };

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const typed = Buffer.concat([Buffer.from(type), data]);
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const sum = Buffer.alloc(4); sum.writeUInt32BE(crc(typed));
  return Buffer.concat([len, typed, sum]);
}
function png(size) {
  const scale = Math.floor(size / 16);
  const pad = Math.floor((size - scale * 16) / 2);
  const raw = Buffer.alloc((size * 3 + 1) * size);
  for (let y = 0; y < size; y++) {
    const row = y * (size * 3 + 1);
    for (let x = 0; x < size; x++) {
      const ch = ART[Math.floor((y - pad) / scale)]?.[Math.floor((x - pad) / scale)] ?? '.';
      Buffer.from(COLORS[ch]).copy(raw, row + 1 + x * 3);
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]);
}

mkdirSync('public/icons', { recursive: true });
for (const size of [96, 180, 192, 512]) writeFileSync(`public/icons/icon-${size}.png`, png(size));

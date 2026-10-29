// Copies the browser libraries and fonts the app loads into app/lib (the Tizen package can't reach node_modules).
import { copyFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const fonts = 'node_modules/@fontsource/roboto/files';
const files = [
  ['node_modules/shaka-player/dist/shaka-player.compiled.js', 'app/lib/shaka-player.compiled.js'],
  // The full build: the light one leaves out alternate audio renditions, and YouTube's live streams carry their audio
  // as one (docs/streaming.md), so live played silent with it.
  ['node_modules/hls.js/dist/hls.min.js', 'app/lib/hls.min.js'],
  ...[400, 500, 700].map((w) => [`${fonts}/roboto-latin-${w}-normal.woff2`, `app/lib/roboto-${w}.woff2`]),
];

mkdirSync(join(root, 'app/lib'), { recursive: true });
for (const [from, to] of files) {
  copyFileSync(join(root, from), join(root, to));
  console.log(`vendored ${to}`);
}

// Manifest.build (app/js/yt/manifest.js) on a VISIONOS-shaped player response.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const src = readFileSync(new URL('../app/js/yt/manifest.js', import.meta.url), 'utf8');
const ctx = {};
vm.runInNewContext(src + '\nthis.Manifest = Manifest;', ctx);
const { Manifest } = ctx;

const ranges = { initRange: { start: '0', end: '741' }, indexRange: { start: '742', end: '1229' } };
const fmt = (itag, mimeType, extra) => ({ itag, mimeType, url: `https://rr1.googlevideo.com/videoplayback?itag=${itag}&c=VISIONOS`, bitrate: itag * 1000, ...ranges, ...extra });

const info = {
  lengthSeconds: 213,
  formats: [
    fmt(137, 'video/mp4; codecs="avc1.640028"', { width: 1920, height: 1080, fps: 25 }),
    fmt(136, 'video/mp4; codecs="avc1.4d401f"', { width: 1280, height: 720, fps: 25 }),
    fmt(298, 'video/mp4; codecs="avc1.4d4020"', { width: 1280, height: 720, fps: 50 }),
    fmt(399, 'video/mp4; codecs="av01.0.08M.08"', { width: 1920, height: 1080, fps: 25 }),
    fmt(313, 'video/webm; codecs="vp9"', { width: 3840, height: 2160, fps: 25 }),
    fmt(140, 'audio/mp4; codecs="mp4a.40.2"', { audioSampleRate: '44100', audioChannels: 2, approxDurationMs: '212091' }),
    fmt(141, 'audio/mp4; codecs="mp4a.40.2"', { isDrc: true, audioSampleRate: '44100', audioChannels: 2 }),
    fmt(251, 'audio/webm; codecs="opus"', { audioSampleRate: '48000', audioChannels: 2 }),
  ],
};

test('H.264 only, one Representation per height, higher fps wins', () => {
  const m = Manifest.build(info, 1080);
  assert.deepEqual([...m.heights], [720, 1080]);
  assert.match(m.mpd, /id="v298"/);
  assert.doesNotMatch(m.mpd, /id="v136"|av01|vp9/);
});

test('best AAC audio without DRC, duration from the audio stream', () => {
  const m = Manifest.build(info, 1080);
  assert.match(m.mpd, /id="a140"/);
  assert.doesNotMatch(m.mpd, /id="a141"|opus/);
  assert.match(m.mpd, /mediaPresentationDuration="PT212\.091S"/);
});

test('maxHeight caps the ladder; BaseURL and ranges are escaped and kept', () => {
  const m = Manifest.build(info, 720);
  assert.deepEqual([...m.heights], [720]);
  assert.match(m.mpd, /<BaseURL>https:\/\/rr1\.googlevideo\.com\/videoplayback\?itag=298&amp;c=VISIONOS<\/BaseURL>/);
  assert.match(m.mpd, /<SegmentBase indexRange="742-1229"><Initialization range="0-741"\/><\/SegmentBase>/);
});

test('no plain-URL formats (ANDROID adaptive) → null, so the player falls back to muxed', () => {
  const ciphered = { lengthSeconds: 10, formats: info.formats.map((f) => ({ ...f, url: undefined })) };
  assert.equal(Manifest.build(ciphered, 1080), null);
});

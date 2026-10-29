// Captions: the player response's caption tracks, fetched as json3 (timed events). VISIONOS tracks load without a
// PO token (docs/streaming.md). Auto-generated tracks roll two lines; showing every active event reproduces that.
var Captions = (function () {
  var cache = {};

  /** [{start, end, text}] in seconds, from a json3 document. */
  function parseJson3(doc) {
    return (doc.events || [])
      .filter((e) => Array.isArray(e.segs))
      .map((e) => ({
        start: (e.tStartMs || 0) / 1000,
        end: ((e.tStartMs || 0) + (e.dDurationMs || 0)) / 1000,
        text: e.segs
          .map((s) => s.utf8 || '')
          .join('')
          .trim(),
      }))
      .filter((c) => c.text);
  }

  async function load(track) {
    if (!cache[track.url]) {
      cache[track.url] = Net.getJson(track.url + '&fmt=json3').then(parseJson3, (e) => {
        delete cache[track.url];
        throw e;
      });
    }
    return cache[track.url];
  }

  /** The text to show at [t]: every cue active then, in order. */
  function at(cues, t) {
    var lines = [];
    for (var i = 0; i < cues.length; i++) {
      var c = cues[i];
      if (c.start > t) break;
      if (t < c.end) lines.push(c.text);
    }
    return lines.slice(-2).join('\n');
  }

  /** The track to use by default: the user's language, a manual track before an auto-generated one. */
  function pick(tracks, lang) {
    var same = tracks.filter((t) => t.lang.split('-')[0] === lang);
    return same.filter((t) => !t.auto)[0] || same[0] || tracks.filter((t) => !t.auto)[0] || null;
  }

  return { load: load, at: at, pick: pick, parseJson3: parseJson3 };
})();

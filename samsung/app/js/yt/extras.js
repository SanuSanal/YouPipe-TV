// SponsorBlock and Return YouTube Dislike: optional, off by default for SponsorBlock (docs/features.md).
var SponsorBlock = (function () {
  /** Categories with their community-standard colours and default actions (as in YouPipe). */
  var CATEGORIES = [
    { key: 'sponsor', label: 'Sponsor', color: '#00d400', action: 'skip' },
    { key: 'selfpromo', label: 'Self promotion', color: '#ffff00', action: 'skip' },
    { key: 'interaction', label: 'Interaction reminder', color: '#cc00ff', action: 'skip' },
    { key: 'intro', label: 'Intro', color: '#00ffff', action: 'show' },
    { key: 'outro', label: 'Endcards and credits', color: '#0202ed', action: 'show' },
    { key: 'preview', label: 'Preview and recap', color: '#008fd6', action: 'show' },
    { key: 'filler', label: 'Filler tangent', color: '#7300ff', action: 'off' },
    { key: 'music_offtopic', label: 'Non-music section', color: '#ff9900', action: 'skip' },
  ];
  var cache = {};

  async function sha256Prefix(text) {
    var bytes = new TextEncoder().encode(text);
    var hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
    return Array.prototype.map.call(hash.slice(0, 2), (b) => b.toString(16).padStart(2, '0')).join('');
  }

  function actionFor(key) {
    var s = Settings.get();
    if (!s.sponsorBlock) return 'off';
    var c = CATEGORIES.filter((x) => x.key === key)[0];
    return (s.sbActions && s.sbActions[key]) || (c ? c.action : 'off');
  }

  /**
   * The video's segments that aren't turned off: [{start, end, category, color, action}]. Uses the hash-prefix
   * endpoint, so only the first 4 hex characters of sha256(videoId) leave the TV.
   */
  async function segments(videoId) {
    if (!Settings.get().sponsorBlock) return [];
    if (!cache[videoId]) {
      cache[videoId] = (async () => {
        var keys = encodeURIComponent(JSON.stringify(CATEGORIES.map((c) => c.key)));
        var data;
        try {
          var prefix = await sha256Prefix(videoId);
          data = await Net.getJson('https://sponsor.ajay.app/api/skipSegments/' + prefix + '?categories=' + keys + '&actionType=skip');
        } catch (e) {
          if (e.status === 404) return []; // no segments for any video with this prefix
          throw e;
        }
        var entry = (data || []).filter((e) => e.videoID === videoId)[0];
        return ((entry && entry.segments) || [])
          .filter((s) => s.segment && s.segment[1] - s.segment[0] >= 1)
          .map((s) => {
            var c = CATEGORIES.filter((x) => x.key === s.category)[0];
            return { start: s.segment[0], end: s.segment[1], category: s.category, label: c ? c.label : s.category, color: c ? c.color : '#fff' };
          })
          .sort((a, b) => a.start - b.start);
      })().catch((e) => {
        delete cache[videoId];
        Log.add('SponsorBlock failed: ' + e.message);
        return [];
      });
    }
    var all = await cache[videoId];
    return all.map((s) => Object.assign({ action: actionFor(s.category) }, s)).filter((s) => s.action !== 'off');
  }

  return { CATEGORIES: CATEGORIES, segments: segments };
})();

var Dislikes = (function () {
  var cache = {};

  /** The estimated dislike count from returnyoutubedislikeapi.com, or null. */
  async function count(videoId) {
    if (!Settings.get().dislikes) return null;
    if (!(videoId in cache)) {
      try {
        var r = await Net.getJson('https://returnyoutubedislikeapi.com/votes?videoId=' + encodeURIComponent(videoId));
        cache[videoId] = typeof r.dislikes === 'number' ? r.dislikes : null;
      } catch (e) {
        Log.add('Return YouTube Dislike failed: ' + e.message);
        return null;
      }
    }
    return cache[videoId];
  }

  return { count: count };
})();

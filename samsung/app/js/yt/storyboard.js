// Seek previews: the player response's storyboard spec, as sprite sheets of frames.
// Spec: "<url with $L and $N>|<level 0>|<level 1>|…", each level "width#height#count#cols#rows#intervalMs#name#sigh".
var Storyboard = (function () {
  /** The largest level of [spec], or null. */
  function parse(spec, lengthSeconds) {
    if (!spec || typeof spec !== 'string') return null;
    var parts = spec.split('|');
    var base = parts.shift();
    if (!base || !parts.length) return null;
    var level = parts.length - 1;
    var f = parts[level].split('#');
    if (f.length < 8) return null;
    var count = Number(f[2]);
    var interval = Number(f[5]) || (lengthSeconds && count ? (lengthSeconds * 1000) / count : 0);
    if (!count || !interval) return null;
    return {
      url: base.replace('$L', String(level)).replace('$N', f[6]) + (base.indexOf('?') >= 0 ? '&' : '?') + 'sigh=' + f[7],
      width: Number(f[0]),
      height: Number(f[1]),
      count: count,
      cols: Number(f[3]),
      rows: Number(f[4]),
      intervalMs: interval,
    };
  }

  /** Where the frame for [seconds] is: {url, x, y, width, height}. */
  function frame(sb, seconds) {
    var i = Math.min(sb.count - 1, Math.max(0, Math.floor((seconds * 1000) / sb.intervalMs)));
    var perPage = sb.cols * sb.rows;
    var page = Math.floor(i / perPage);
    var inPage = i % perPage;
    return {
      url: sb.url.replace('$M', String(page)),
      x: (inPage % sb.cols) * sb.width,
      y: Math.floor(inPage / sb.cols) * sb.height,
      width: sb.width,
      height: sb.height,
      sheetWidth: sb.cols * sb.width,
      sheetHeight: sb.rows * sb.height,
    };
  }

  return { parse: parse, frame: frame };
})();

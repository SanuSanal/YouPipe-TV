// Text formatting shared by the screens.
var Format = (function () {
  /** 75 → "1:15", 3725 → "1:02:05". */
  function time(s) {
    if (!isFinite(s) || s < 0) return '--:--';
    s = Math.floor(s);
    var h = Math.floor(s / 3600);
    var m = Math.floor((s % 3600) / 60);
    var sec = String(s % 60).padStart(2, '0');
    return h ? h + ':' + String(m).padStart(2, '0') + ':' + sec : m + ':' + sec;
  }

  /** "1:02:05" → 3725; null when it isn't a duration. */
  function parseTime(text) {
    if (!text || !/^\d+(:\d\d){1,2}$/.test(text.trim())) return null;
    return text
      .trim()
      .split(':')
      .reduce((acc, p) => acc * 60 + Number(p), 0);
  }

  /** 1234567 → "1.2M". */
  function count(n) {
    if (n == null || !isFinite(n)) return '';
    if (n < 1000) return String(n);
    var units = [
      [1e9, 'B'],
      [1e6, 'M'],
      [1e3, 'K'],
    ];
    for (var i = 0; i < units.length; i++) {
      if (n >= units[i][0]) {
        var v = n / units[i][0];
        return (v < 10 ? v.toFixed(1).replace(/\.0$/, '') : Math.floor(v)) + units[i][1];
      }
    }
    return String(n);
  }

  /** A date (ms) as "3 days ago". */
  function ago(ms) {
    var s = Math.max(0, (Date.now() - ms) / 1000);
    var units = [
      [31536000, 'year'],
      [2592000, 'month'],
      [604800, 'week'],
      [86400, 'day'],
      [3600, 'hour'],
      [60, 'minute'],
    ];
    for (var i = 0; i < units.length; i++) {
      var n = Math.floor(s / units[i][0]);
      if (n >= 1) return n + ' ' + units[i][1] + (n === 1 ? '' : 's') + ' ago';
    }
    return 'just now';
  }

  return { time: time, parseTime: parseTime, count: count, ago: ago };
})();

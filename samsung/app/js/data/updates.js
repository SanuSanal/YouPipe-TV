// Update checks (docs/release.md): the latest GitHub release, at most once a day after Home loads, and whenever
// Settings → Version asks. "yp.updates" keeps {checkedAt, latest, notified}, the same as the Android app. A Samsung TV
// can't install the new version by itself, so the prompt says where to get it.
var Updates = (function () {
  var REPO = 'SanuSanal/YouPipe-TV';
  var DAY = 24 * 3600 * 1000;

  function saved() {
    return Store.get('updates', null) || {};
  }

  /** The latest release's version; a daily check answers from the last one when it ran less than a day ago. */
  async function check(force) {
    var s = saved();
    var latest = s.latest;
    if (force || !latest || Date.now() - (s.checkedAt || 0) > DAY) {
      var r = await Net.getJson('https://api.github.com/repos/' + REPO + '/releases/latest');
      latest = String(r.tag_name || '').replace(/^v/, '');
      if (!latest) throw new Error('no release yet');
      Store.set('updates', Object.assign({}, saved(), { checkedAt: Date.now(), latest: latest }));
    }
    return latest;
  }

  /** A newer version than this one that a check has found, or null. */
  function available() {
    var latest = saved().latest;
    return latest && isNewer(latest, Platform.version()) ? latest : null;
  }

  /** A newer version the start-up prompt hasn't offered yet; each is offered once (offered()). */
  async function toOffer() {
    if (Platform.version() === 'dev') return null;
    var latest = await check(false);
    return isNewer(latest, Platform.version()) && saved().notified !== latest ? latest : null;
  }

  function offered(version) {
    Store.set('updates', Object.assign({}, saved(), { notified: version }));
  }

  /** Whether version a is newer than b (MAJOR.MINOR.PATCH); a 'dev' build counts as older than any release. */
  function isNewer(a, b) {
    function parts(v) {
      return String(v)
        .split('.')
        .map((p) => (/^\d+$/.test(p) ? Number(p) : -1));
    }
    var x = parts(a);
    var y = parts(b);
    if (x.some((p) => p < 0)) return false;
    if (y.some((p) => p < 0)) return true;
    for (var i = 0; i < 3; i++) {
      var d = (x[i] || 0) - (y[i] || 0);
      if (d) return d > 0;
    }
    return false;
  }

  /** The prompt for a newer version. */
  function offer(version) {
    Overlay.confirm(
      'YouPipe ' + version + ' is available',
      'OK',
      () => {},
      'You have ' + Platform.version() + '. Install it from a computer the same way as the first time: sanusanal.github.io/YouPipe-TV',
      { noCancel: true },
    );
  }

  return { REPO: REPO, check: check, available: available, toOffer: toOffer, offered: offered, isNewer: isNewer, offer: offer };
})();

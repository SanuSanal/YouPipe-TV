// The self test (docs/testing.md): Settings → Run the self test, ?selftest in a browser, or tools/tv.ps1 -SelfTest.
// It plays through the real player screen. Each line is logged as "SELFTEST|<case>|PASS|FAIL|<detail>".
// Test plays don't go into the watch history.
var SelfTest = (function () {
  var VODS = [
    ['aqz-KE-bpKQ', 'Big Buck Bunny, 1080p60, 10 min'],
    ['dQw4w9WgXcQ', 'music video, 3.5 min'],
    ['9bZkp7q19f0', 'music video, 4 min'],
    ['Scm5tqflAjE', 'made for kids: VISIONOS refuses it, ANDROID muxed 360p'],
  ];
  var running = false;

  function report(name, ok, detail) {
    Log.add('SELFTEST|' + name + '|' + (ok ? 'PASS' : 'FAIL') + '|' + detail);
    return ok;
  }

  /** Resolves once playback has advanced [seconds] past where it was, or rejects after [timeoutMs]. */
  function waitForProgress(video, seconds, timeoutMs) {
    var from = null;
    return new Promise((resolve, reject) => {
      var started = Date.now();
      var timer = setInterval(() => {
        if (from === null && video.readyState >= 2 && !video.paused) from = video.currentTime;
        if (from !== null && video.currentTime - from >= seconds) {
          clearInterval(timer);
          resolve(Date.now() - started);
        } else if (Date.now() - started > timeoutMs) {
          clearInterval(timer);
          reject(new Error('stuck at ' + video.currentTime.toFixed(1) + ' s (readyState ' + video.readyState + ')'));
        }
      }, 250);
    });
  }

  function closePlayer() {
    while (Router.top() && Router.top().el.classList.contains('screen-watch') && Router.pop()) {}
  }

  async function playCase(name, item, fraction) {
    var t0 = Date.now();
    try {
      Watch.open(item, { startFraction: fraction, noHistory: true });
      await waitForProgress(Player.video, 0.5, 30000);
      var startMs = Date.now() - t0;
      await waitForProgress(Player.video, 5, 30000);
      var info = Watch.state && Watch.state.info;
      var v = Player.video;
      // A stream that plays without sound passed before (live with hls.js's light build), so sound is checked too.
      if (Player.hasAudio() === false) return report(name, false, 'plays without sound (' + Player.quality() + ')');
      return report(
        name,
        true,
        (info && info.isLive ? 'live' : 'at ' + Math.round(v.currentTime) + '/' + Math.round(v.duration) + ' s') +
          ', ' + v.videoWidth + 'x' + v.videoHeight + ', playing after ' + startMs + ' ms, ' + Player.quality(),
      );
    } catch (e) {
      return report(name, false, e.message);
    } finally {
      closePlayer();
    }
  }

  async function run() {
    if (running) return;
    running = true;
    Log.toggle(true);
    Log.add('SELFTEST start, ' + navigator.userAgent);
    var passed = 0;
    var total = 0;
    async function step(fn) {
      total++;
      if (await fn()) passed++;
    }
    try {
      await step(async () => {
        try {
          var v = await InnerTube.ensureVisitor();
          return report('visitor', true, v.slice(0, 12) + '…');
        } catch (e) {
          return report('visitor', false, e.message);
        }
      });
      await step(async () => {
        try {
          var items = Parse.flatten((await InnerTube.search('big buck bunny')).entries).filter((i) => i.type === 'video');
          return report('search', items.length >= 5, items.length + ' videos');
        } catch (e) {
          return report('search', false, e.message);
        }
      });
      await step(async () => {
        try {
          var m = await InnerTube.next('aqz-KE-bpKQ');
          return report('watch page', !!m.title && m.related.length > 0, m.related.length + ' related, channel ' + m.channel.name);
        } catch (e) {
          return report('watch page', false, e.message);
        }
      });
      for (var i = 0; i < VODS.length; i++) {
        var v = VODS[i];
        await step(() => playCase('vod ' + v[0] + ' (' + v[1] + ') from 75%', { type: 'video', id: v[0], title: v[1] }, 0.75));
      }
      await step(async () => {
        try {
          var live = Parse.flatten((await InnerTube.search('news', InnerTube.FILTER.LIVE)).entries).filter((x) => x.live)[0];
          if (!live) return report('live', false, 'no live stream in the search results');
          return await playCase('live ' + live.id + ' (' + live.channel + ')', live, 0);
        } catch (e) {
          return report('live', false, e.message);
        }
      });
    } finally {
      running = false;
    }
    Log.add('SELFTEST done: ' + passed + '/' + total + ' passed');
    return { passed: passed, total: total };
  }

  return { run: run };
})();

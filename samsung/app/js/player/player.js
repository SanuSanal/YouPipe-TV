// Playback (MSE), one engine per source (docs/streaming.md):
// - VODs: Shaka Player with our DASH manifest (manifest.js).
// - Live: hls.js with YouTube's HLS manifest. Its audio renditions are packed ADTS AAC with an ID3 timestamp while
//   the video is MPEG-TS; Shaka treats both as TS and never appends the audio, hls.js handles it.
// - Made-for-kids fallback: the ANDROID client's muxed 360p, straight in <video src>.
// Only one engine owns the <video> at a time: Shaka is attached for a VOD and detached afterwards.
var Player = (function () {
  var video = null;
  var shakaPlayer = null;
  var hls = null;
  var engine = null; // 'dash' | 'hls' | 'muxed'
  var muxedHeight = 0;
  var hlsAudio = false; // whether hls.js made an audio buffer (live)

  async function init() {
    shaka.polyfill.installAll();
    if (!shaka.Player.isBrowserSupported()) throw new Error('Shaka Player: this browser is not supported');
    video = document.getElementById('video');
    shakaPlayer = new shaka.Player();
    shakaPlayer.configure({
      streaming: {
        bufferingGoal: 30,
        rebufferingGoal: 2,
        bufferBehind: 30,
        retryParameters: { maxAttempts: 3, baseDelay: 500, timeout: 20000 },
      },
      abr: { enabled: true, defaultBandwidthEstimate: 8e6 },
    });
    if (Net.viaProxy) useDevProxy();
    shakaPlayer.addEventListener('error', (e) => Log.add('shaka error ' + describe(e.detail)));
    shakaPlayer.addEventListener('adaptation', () => Log.add('quality ' + quality()));
    return video;
  }

  /** In a desktop browser, Shaka fetches https through the dev server's proxy (Net.url); the TV fetches directly. */
  function useDevProxy() {
    var parse = shaka.net.HttpFetchPlugin.parse;
    shaka.net.NetworkingEngine.registerScheme(
      'https',
      (uri, request, type, progress, headersReceived, config) =>
        parse(Net.url(uri), request, type, progress, headersReceived, config).chain((response) => {
          response.uri = uri;
          response.originalUri = uri;
          return response;
        }),
      shaka.net.NetworkingEngine.PluginPriority.APPLICATION,
    );
  }

  function describe(err) {
    if (!err) return '?';
    return 'code=' + err.code + ' category=' + err.category + (err.data ? ' ' + JSON.stringify(err.data).slice(0, 200) : '');
  }

  /** The highest height to play: the Video quality setting, at most 1080p. */
  function maxHeight() {
    var q = Settings.get().quality;
    return q === 'auto' ? 1080 : Number(q) || 1080;
  }

  async function loadDash(info, start) {
    var m = Manifest.build(info, 1080);
    if (!m) throw new Error('No DASH formats (' + info.formats.length + ' adaptive formats)');
    shakaPlayer.configure({ abr: { enabled: true, restrictions: { maxHeight: maxHeight() } } });
    await shakaPlayer.attach(video);
    var uri = 'data:application/dash+xml;base64,' + btoa(unescape(encodeURIComponent(m.mpd)));
    await shakaPlayer.load(uri, start || 0, 'application/dash+xml');
    engine = 'dash';
    return 'DASH ' + m.heights.join('/') + 'p';
  }

  /** A progressive stream plays straight from <video src>: no MSE, and media elements need no CORS. */
  function loadMuxed(info, start) {
    muxedHeight = info.muxed.height;
    engine = 'muxed';
    video.src = info.muxed.url;
    if (start) video.currentTime = start;
    return 'muxed ' + info.muxed.height + 'p';
  }

  function loadHls(uri) {
    return new Promise((resolve, reject) => {
      hls = new Hls({
        // YouTube's playlists use absolute URLs, so swapping the URL at open() is enough for the dev proxy.
        xhrSetup: Net.viaProxy ? (xhr, url) => xhr.open('GET', Net.url(url), true) : undefined,
        maxBufferLength: 30,
        capLevelToPlayerSize: false,
      });
      engine = 'hls';
      hlsAudio = false;
      hls.on(Hls.Events.BUFFER_CREATED, (e, d) => {
        hlsAudio = !!(d.tracks && (d.tracks.audio || d.tracks.audiovideo));
      });
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        var cap = maxHeight();
        var allowed = hls.levels.map((l, i) => (l.height <= cap ? i : -1)).filter((i) => i >= 0);
        if (allowed.length && allowed.length < hls.levels.length) hls.autoLevelCapping = allowed[allowed.length - 1];
        resolve('HLS ' + hls.levels.map((l) => l.height).join('/') + 'p');
      });
      hls.on(Hls.Events.LEVEL_SWITCHED, () => Log.add('quality ' + quality()));
      hls.on(Hls.Events.ERROR, (e, d) => {
        Log.add('hls error ' + d.type + ' ' + d.details + (d.fatal ? ' (fatal)' : ''));
        if (d.fatal) reject(new Error('HLS ' + d.details));
      });
      hls.loadSource(uri);
      hls.attachMedia(video);
    });
  }

  /** Loads a resolved player response (InnerTube.player) and starts at [start] seconds (VODs). */
  async function load(info, start) {
    await stop();
    var t0 = Date.now();
    var kind;
    if (info.isLive && info.hlsUrl) kind = await loadHls(info.hlsUrl);
    else if (Manifest.build(info, 1080)) kind = await loadDash(info, start);
    else if (info.muxed) kind = loadMuxed(info, start);
    else throw new Error('No playable stream (' + info.formats.length + ' adaptive formats)');
    video.playbackRate = Settings.get().speed || 1;
    Log.add('loaded ' + info.id + ' ' + kind + ' from ' + info.client + ' (' + (Date.now() - t0) + ' ms)');
    return kind;
  }

  /** The heights the user can pick from, highest first. */
  function heights() {
    if (engine === 'dash') {
      var seen = {};
      return shakaPlayer
        .getVariantTracks()
        .map((t) => t.height)
        .filter((hgt) => hgt && !seen[hgt] && (seen[hgt] = 1))
        .sort((a, b) => b - a);
    }
    if (engine === 'hls' && hls) return hls.levels.map((l) => l.height).filter((v, i, a) => a.indexOf(v) === i).sort((a, b) => b - a);
    return muxedHeight ? [muxedHeight] : [];
  }

  /** 'auto' or the fixed height. */
  function selectedHeight() {
    if (engine === 'dash') return shakaPlayer.getConfiguration().abr.enabled ? 'auto' : (activeDash() || {}).height;
    if (engine === 'hls' && hls) return hls.autoLevelEnabled ? 'auto' : (hls.levels[hls.currentLevel] || {}).height;
    return muxedHeight || 'auto';
  }

  function activeDash() {
    return shakaPlayer.getVariantTracks().filter((v) => v.active)[0];
  }

  function setHeight(h) {
    if (engine === 'dash') {
      if (h === 'auto') return shakaPlayer.configure({ abr: { enabled: true } });
      shakaPlayer.configure({ abr: { enabled: false } });
      var tracks = shakaPlayer.getVariantTracks().filter((t) => t.height === h);
      var best = tracks.sort((a, b) => b.bandwidth - a.bandwidth)[0];
      if (best) shakaPlayer.selectVariantTrack(best, true);
    } else if (engine === 'hls' && hls) {
      if (h === 'auto') hls.currentLevel = -1;
      else hls.currentLevel = hls.levels.findIndex((l) => l.height === h);
    }
  }

  /**
   * Whether the playing stream has sound: DASH's active variant has an audio codec, hls.js made an audio buffer, or
   * the muxed stream (always with audio). Null before anything plays. The self test checks it.
   */
  function hasAudio() {
    if (engine === 'dash') return shakaPlayer.getVariantTracks().some((t) => t.active && !!t.audioCodec);
    if (engine === 'hls') return hlsAudio;
    if (engine === 'muxed') return true;
    return null;
  }

  function quality() {
    if (engine === 'muxed') return muxedHeight + 'p';
    if (engine === 'hls' && hls) {
      var level = hls.levels[hls.currentLevel];
      return level ? level.height + 'p' : '';
    }
    var t = shakaPlayer && activeDash();
    return t ? t.height + 'p' : '';
  }

  async function stop() {
    if (!video) return;
    video.pause();
    if (hls) {
      hls.destroy();
      hls = null;
    }
    muxedHeight = 0;
    engine = null;
    if (shakaPlayer.getMediaElement()) await shakaPlayer.detach();
    video.removeAttribute('src');
    video.load();
  }

  return {
    init: init,
    load: load,
    stop: stop,
    quality: quality,
    hasAudio: hasAudio,
    heights: heights,
    selectedHeight: selectedHeight,
    setHeight: setHeight,
    get video() {
      return video;
    },
    get engine() {
      return engine;
    },
    /** The Shaka player, for diagnostics from the Web Inspector. */
    get shaka() {
      return shakaPlayer;
    },
    /** The hls.js instance while a live stream plays, for diagnostics. */
    get hls() {
      return hls;
    },
  };
})();

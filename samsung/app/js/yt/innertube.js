// InnerTube, called from the TV (docs/architecture.md).
// - Browse, search, next and comments: the WEB client, like YouPipe's lib/innertube.
// - Streams: the VISIONOS client, the one NewPipeExtractor v0.26.5 takes its DASH streams from. Its formats carry
//   plain URLs (no signature cipher, no n parameter, no PO token) that play from a browser (docs/streaming.md).
var InnerTube = (function () {
  var BASE = 'https://www.youtube.com/youtubei/v1/';
  var WEB = { clientName: 'WEB', clientVersion: '2.20260120.01.00' };
  var VISIONOS = {
    clientName: 'VISIONOS',
    clientVersion: '1.02',
    deviceMake: 'Apple',
    deviceModel: 'RealityDevice14,1',
    osName: 'visionOS',
    osVersion: '25.6.0.23O471',
    platform: 'MOBILE',
    clientScreen: 'WATCH',
  };
  // The fallback when VISIONOS refuses a video (made-for-kids videos: "This video is not available"). Like YouPipe's
  // muxed fallback, only its progressive 360p stream (itag 18) is used: its adaptive formats have no plain URL.
  // (IOS also answers, but its URLs stop at about 1 MB on those videos: the PO-token cap.)
  var ANDROID = {
    clientName: 'ANDROID',
    clientVersion: '21.03.36',
    platform: 'MOBILE',
    osName: 'Android',
    osVersion: '15',
    androidSdkVersion: 35,
  };

  /** Search filters, as the `params` blobs youtube.com sends for its filter chips. */
  var FILTER = {
    LIVE: 'EgJAAQ==',
    VIDEOS: 'EgIQAQ==',
    THIS_WEEK_VIDEOS: 'EgQIAxAB',
  };

  var visitorData = Store.get('visitorData', null);

  function locale() {
    var s = Settings.get();
    return { hl: s.hl || (navigator.language || 'en').split('-')[0], gl: s.gl || 'US' };
  }

  function context(client) {
    var l = locale();
    return { client: Object.assign({ hl: l.hl, gl: l.gl, visitorData: visitorData || undefined }, client) };
  }

  async function ensureVisitor() {
    if (visitorData) return visitorData;
    var r = await Net.postJson(BASE + 'visitor_id?prettyPrint=false', { context: context(WEB) });
    visitorData = r.responseContext && r.responseContext.visitorData;
    if (!visitorData) throw new Error('visitor_id returned no visitorData');
    Store.set('visitorData', visitorData);
    return visitorData;
  }

  async function post(endpoint, body, client) {
    await ensureVisitor();
    return Net.postJson(BASE + endpoint + '?prettyPrint=false', Object.assign({ context: context(client || WEB) }, body));
  }

  // Browse and search ---------------------------------------------------------------------------------------------

  /** Search: {entries, continuation}. [params] is a filter blob (FILTER). */
  async function search(query, params) {
    var body = { query: query };
    if (params) body.params = params;
    return Parse.search(await post('search', body));
  }

  async function searchMore(token) {
    return Parse.page(await post('search', { continuation: token }));
  }

  /** Autocomplete, from Google's suggest service (the same one youtube.com uses). */
  async function suggestions(input) {
    var l = locale();
    var u =
      'https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&hl=' + l.hl + '&gl=' + l.gl + '&q=' + encodeURIComponent(input);
    var data = await Net.getJson(u);
    return Array.isArray(data) && Array.isArray(data[1]) ? data[1].filter((s) => typeof s === 'string') : [];
  }

  /** A channel page; [params] picks a tab (from page.tabs), Home when null. */
  async function channel(id, params) {
    var body = { browseId: id };
    if (params) body.params = params;
    return Parse.channelPage(await post('browse', body), id);
  }

  /** More of a browse list (channel tab, playlist), or a channel tab re-sorted by a sort chip's token. */
  async function browseMore(token) {
    return Parse.page(await post('browse', { continuation: token }));
  }

  async function playlist(id) {
    return Parse.playlistPage(await post('browse', { browseId: 'VL' + id }), id);
  }

  async function playlistMore(token) {
    var data = await post('browse', { continuation: token });
    var p = Parse.page(data);
    return { videos: Parse.flatten(p.entries).filter((i) => i.type === 'video'), continuation: p.continuation };
  }

  /** The watch page (details, chapters, related videos, comments token). */
  async function next(videoId, playlistId) {
    var body = { videoId: videoId };
    if (playlistId) body.playlistId = playlistId;
    return Parse.watch(await post('next', body));
  }

  async function nextMore(token) {
    var p = Parse.page(await post('next', { continuation: token }));
    return { items: Parse.flatten(p.entries), continuation: p.continuation };
  }

  /** A page of comments: the first page from the watch page's token, then each continuation. */
  async function comments(token) {
    return Parse.comments(await post('next', { continuation: token }));
  }

  // Streams -------------------------------------------------------------------------------------------------------

  /** The player response, reduced to what playback needs: VISIONOS first, then ANDROID. */
  async function player(videoId) {
    var info = null;
    var clients = [VISIONOS, ANDROID];
    for (var i = 0; i < clients.length; i++) {
      info = await playerFrom(clients[i], videoId);
      if (info.status === 'OK') break;
      Log.add(clients[i].clientName + ' refused ' + videoId + ': ' + info.status + ' ' + info.reason);
    }
    return info;
  }

  async function playerFrom(client, videoId) {
    var r = await post('player', { videoId: videoId, contentCheckOk: true, racyCheckOk: true }, client);
    var ps = r.playabilityStatus || {};
    var sd = r.streamingData || {};
    var vd = r.videoDetails || {};
    return {
      id: videoId,
      client: client.clientName,
      status: ps.status,
      reason: ps.reason || (ps.errorScreen && Parse.text(Parse.nav(ps.errorScreen, ['playerErrorMessageRenderer', 'reason']))) || '',
      title: vd.title || '',
      channel: vd.author || '',
      channelId: vd.channelId || null,
      description: vd.shortDescription || '',
      views: Number(vd.viewCount || 0),
      lengthSeconds: Number(vd.lengthSeconds || 0),
      isLive: !!vd.isLive,
      thumb: Parse.bestImage(vd.thumbnail) || Parse.thumbOf(videoId),
      formats: sd.adaptiveFormats || [],
      muxed: (sd.formats || []).filter((f) => f.url).sort((a, b) => b.height - a.height)[0] || null,
      hlsUrl: sd.hlsManifestUrl || null,
      expiresInSeconds: Number(sd.expiresInSeconds || 0),
      storyboard: Storyboard.parse(Parse.nav(r, ['storyboards', 'playerStoryboardSpecRenderer', 'spec']), Number(vd.lengthSeconds || 0)),
      captions: (Parse.nav(r, ['captions', 'playerCaptionsTracklistRenderer', 'captionTracks']) || []).map((t) => ({
        url: t.baseUrl,
        lang: t.languageCode || '',
        name: Parse.text(t.name) || t.languageCode || '',
        auto: t.kind === 'asr',
      })),
    };
  }

  return {
    FILTER: FILTER,
    ensureVisitor: ensureVisitor,
    search: search,
    searchMore: searchMore,
    suggestions: suggestions,
    channel: channel,
    browseMore: browseMore,
    playlist: playlist,
    playlistMore: playlistMore,
    next: next,
    nextMore: nextMore,
    comments: comments,
    player: player,
  };
})();

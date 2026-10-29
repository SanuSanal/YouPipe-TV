// The subscriptions feed without an account (docs/data.md): every subscribed channel's latest uploads, newest
// first, cached on the TV (Store "subsFeed") and refreshed at most every 30 minutes.
var SubsFeed = (function () {
  var MIN_INTERVAL = 30 * 60 * 1000;
  var KEEP_DAYS = 60;
  var running = null;

  function cached() {
    return Store.get('subsFeed', { at: 0, videos: [] });
  }

  function save(videos) {
    var cutoff = Date.now() - KEEP_DAYS * 864e5;
    var byId = {};
    videos.forEach((v) => {
      if (v.publishedAt >= cutoff) byId[v.id] = v;
    });
    var all = Object.keys(byId)
      .map((k) => byId[k])
      .sort((a, b) => b.publishedAt - a.publishedAt)
      .slice(0, 600);
    Store.set('subsFeed', { at: Date.now(), videos: all });
    return all;
  }

  /** The cached feed with relative dates filled in, newest first. Shorts are left out unless [withShorts]. */
  function videos(withShorts) {
    var subs = {};
    Library.subscriptions().forEach((s) => (subs[s.id] = s));
    return cached()
      .videos.filter((v) => subs[v.channelId] && (withShorts || !v.short))
      .map((v) => Object.assign({}, v, { published: Format.ago(v.publishedAt), avatar: subs[v.channelId].avatar }));
  }

  /** Refreshes every channel (six at a time), unless the feed is fresh and not [force]d. */
  function refresh(force) {
    if (!force && Date.now() - cached().at < MIN_INTERVAL) return Promise.resolve(videos());
    if (running) return running;
    running = (async () => {
      var subs = Library.subscriptions();
      var collected = [];
      var next = 0;
      async function worker() {
        while (next < subs.length) {
          var s = subs[next++];
          try {
            collected.push.apply(collected, await ChannelFeed.latest(s.id, s.name));
          } catch (e) {
            Log.add('feed ' + s.name + ' failed: ' + e.message);
          }
        }
      }
      await Promise.all([worker(), worker(), worker(), worker(), worker(), worker()]);
      // Keep what an unreachable channel had before.
      var fetched = {};
      collected.forEach((v) => (fetched[v.channelId] = 1));
      save(collected.concat(cached().videos.filter((v) => !fetched[v.channelId])));
      return videos();
    })().finally(() => (running = null));
    return running;
  }

  async function refreshChannel(channel) {
    try {
      var latest = await ChannelFeed.latest(channel.id, channel.name);
      save(cached().videos.concat(latest));
    } catch (e) {
      Log.add('feed ' + channel.name + ' failed: ' + e.message);
    }
  }

  function dropChannel(channelId) {
    var c = cached();
    Store.set('subsFeed', { at: c.at, videos: c.videos.filter((v) => v.channelId !== channelId) });
  }

  return { videos: videos, refresh: refresh, refreshChannel: refreshChannel, dropChannel: dropChannel };
})();

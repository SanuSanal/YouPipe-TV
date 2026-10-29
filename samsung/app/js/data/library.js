// The user's library, kept on the TV (docs/data.md): watch history with progress, subscriptions, Watch later, liked
// videos, saved playlists and search history. Nothing leaves the TV.
var Library = (function () {
  var LIMITS = { history: 500, watchLater: 500, liked: 1000, playlists: 200, searches: 30 };
  var listeners = [];

  function changed(what) {
    listeners.forEach((fn) => fn(what));
  }

  function onChange(fn) {
    listeners.push(fn);
  }

  /** Only what the cards need, so stored items stay small. */
  function slim(item) {
    var keys =
      item.type === 'channel'
        ? ['type', 'id', 'name', 'avatar', 'subs']
        : item.type === 'playlist'
          ? ['type', 'id', 'title', 'thumb', 'channel', 'count']
          : ['type', 'id', 'title', 'channel', 'channelId', 'avatar', 'thumb', 'duration', 'views', 'published', 'live', 'short'];
    var out = {};
    keys.forEach((k) => {
      if (item[k] != null) out[k] = item[k];
    });
    return out;
  }

  function listOf(key) {
    return Store.get(key, []);
  }

  function has(key, id) {
    return listOf(key).some((x) => (x.id || (x.video && x.video.id)) === id);
  }

  function toggle(key, item) {
    var l = listOf(key);
    var i = l.findIndex((x) => x.id === item.id);
    if (i >= 0) l.splice(i, 1);
    else l.unshift(slim(item));
    Store.set(key, l.slice(0, LIMITS[key] || 500));
    changed(key);
    return i < 0;
  }

  function remove(key, id) {
    Store.set(
      key,
      listOf(key).filter((x) => (x.id || (x.video && x.video.id)) !== id),
    );
    changed(key);
  }

  // History: [{video, position, duration, at}], newest first ------------------------------------------------------

  function history() {
    return listOf('history');
  }

  function progress(videoId) {
    return history().filter((h) => h.video.id === videoId)[0] || null;
  }

  function saveProgress(video, position, duration) {
    if (!video || !video.id) return;
    var l = history().filter((h) => h.video.id !== video.id);
    l.unshift({ video: slim(Object.assign({ type: 'video' }, video)), position: Math.floor(position || 0), duration: Math.floor(duration || 0), at: Date.now() });
    Store.set('history', l.slice(0, LIMITS.history));
    changed('history');
  }

  /** Videos started but not finished, newest first. */
  function continueWatching() {
    return history()
      .filter((h) => !h.video.live && h.duration > 60 && h.position > 15 && h.position < h.duration * 0.9)
      .map((h) => Object.assign({}, h.video, { progress: h.position / h.duration }));
  }

  // Subscriptions -------------------------------------------------------------------------------------------------

  function subscriptions() {
    return listOf('subs');
  }

  function isSubscribed(channelId) {
    return has('subs', channelId);
  }

  /** Subscribes or unsubscribes; returns true when now subscribed. */
  function toggleSubscription(channel) {
    var now = toggle('subs', { type: 'channel', id: channel.id, name: channel.name, avatar: channel.avatar });
    if (now) SubsFeed.refreshChannel(channel);
    else SubsFeed.dropChannel(channel.id);
    return now;
  }

  // Search history --------------------------------------------------------------------------------------------------

  function searches() {
    return listOf('searches');
  }

  function addSearch(q) {
    q = q.trim();
    if (!q) return;
    var l = searches().filter((s) => s.toLowerCase() !== q.toLowerCase());
    l.unshift(q);
    Store.set('searches', l.slice(0, LIMITS.searches));
  }

  function clear(key) {
    Store.set(key, []);
    changed(key);
  }

  return {
    onChange: onChange,
    slim: slim,
    listOf: listOf,
    has: has,
    toggle: toggle,
    remove: remove,
    history: history,
    progress: progress,
    saveProgress: saveProgress,
    continueWatching: continueWatching,
    subscriptions: subscriptions,
    isSubscribed: isSubscribed,
    toggleSubscription: toggleSubscription,
    searches: searches,
    addSearch: addSearch,
    clear: clear,
  };
})();

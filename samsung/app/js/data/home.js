// The Home rows. Signed out, YouTube's own Home is empty until there's watch history on its side, so like YouPipe the
// rows are built on the TV (docs/data.md): continue watching, recommendations from what was watched (related
// videos), new uploads from subscriptions, then topic rows from searches.
//
// A source is {title, load(): Promise<items>, more(): Promise<items>, hasMore()}: load gives the first page.
var Home = (function () {
  var TOPICS = [
    ['Music', 'music', InnerTube.FILTER.THIS_WEEK_VIDEOS],
    ['Live now', 'live', InnerTube.FILTER.LIVE],
    ['Gaming', 'gaming', InnerTube.FILTER.THIS_WEEK_VIDEOS],
    ['News', 'news today', InnerTube.FILTER.THIS_WEEK_VIDEOS],
    ['Sports', 'sports highlights', InnerTube.FILTER.THIS_WEEK_VIDEOS],
    ['Comedy', 'comedy', InnerTube.FILTER.THIS_WEEK_VIDEOS],
    ['Science and tech', 'science technology', InnerTube.FILTER.THIS_WEEK_VIDEOS],
    ['Cooking', 'cooking recipes', InnerTube.FILTER.THIS_WEEK_VIDEOS],
    ['Podcasts', 'podcast', InnerTube.FILTER.THIS_WEEK_VIDEOS],
    ['Travel', 'travel vlog', InnerTube.FILTER.THIS_WEEK_VIDEOS],
  ];

  /** Long videos only: no Shorts on the TV's Home. */
  function playable(items) {
    return items.filter((i) => i.type === 'video' && !i.short);
  }

  function listSource(title, items) {
    return {
      title: title,
      load: () => Promise.resolve(items),
      more: () => Promise.resolve([]),
      hasMore: () => false,
    };
  }

  function searchSource(title, query, params) {
    var token = null;
    var started = false;
    return {
      title: title,
      load: async () => {
        started = true;
        var p = await InnerTube.search(query, params);
        token = p.continuation;
        return playable(Parse.flatten(p.entries));
      },
      more: async () => {
        if (!token) return [];
        var p = await InnerTube.searchMore(token);
        token = p.continuation;
        return playable(Parse.flatten(p.entries));
      },
      hasMore: () => !started || !!token,
    };
  }

  /** Related videos of several seeds, interleaved; finished videos are left out. */
  function relatedSource(title, seeds, exclude) {
    var tokens = [];
    var seen = {};
    function fresh(items) {
      return playable(items).filter((i) => !exclude[i.id] && !seen[i.id] && (seen[i.id] = 1));
    }
    function interleave(lists) {
      var out = [];
      for (var i = 0; lists.some((l) => i < l.length); i++) lists.forEach((l) => i < l.length && out.push(l[i]));
      return out;
    }
    return {
      title: title,
      load: async () => {
        var pages = await Promise.all(seeds.map((s) => InnerTube.next(s).catch(() => null)));
        tokens = pages.filter(Boolean).map((p) => p.relatedContinuation).filter(Boolean);
        return fresh(interleave(pages.filter(Boolean).map((p) => p.related)));
      },
      more: async () => {
        var current = tokens;
        tokens = [];
        var pages = await Promise.all(current.map((t) => InnerTube.nextMore(t).catch(() => null)));
        tokens = pages.filter(Boolean).map((p) => p.continuation).filter(Boolean);
        return fresh(interleave(pages.filter(Boolean).map((p) => p.items)));
      },
      hasMore: () => tokens.length > 0,
    };
  }

  function subscriptionsSource() {
    return {
      title: 'Latest from your subscriptions',
      load: async () => {
        var cached = SubsFeed.videos();
        var fresh = SubsFeed.refresh(false);
        return (cached.length ? cached : await fresh).slice(0, 40);
      },
      more: () => Promise.resolve([]),
      hasMore: () => false,
    };
  }

  function shuffle(a) {
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1));
      var t = a[i];
      a[i] = a[j];
      a[j] = t;
    }
    return a;
  }

  /** The rows, in order. */
  function sources() {
    var out = [];
    var cw = Library.continueWatching();
    if (cw.length) out.push(listSource('Continue watching', cw.slice(0, 30)));
    var history = Library.history();
    var finished = {};
    history.forEach((h) => {
      if (h.duration && h.position > h.duration * 0.9) finished[h.video.id] = 1;
    });
    var seeds = history
      .filter((h) => !h.video.short)
      .slice(0, 6)
      .map((h) => h.video.id);
    if (seeds.length) out.push(relatedSource('Recommended', seeds, finished));
    if (Library.subscriptions().length) out.push(subscriptionsSource());
    if (history[0]) out.push(relatedSource('Because you watched ' + history[0].video.title, [history[0].video.id], finished));
    var topics = shuffle(TOPICS.slice(2)); // Music and Live now stay first
    TOPICS.slice(0, 2)
      .concat(topics)
      .forEach((t) => out.push(searchSource(t[0], t[1], t[2])));
    return out;
  }

  return { sources: sources, searchSource: searchSource, listSource: listSource };
})();

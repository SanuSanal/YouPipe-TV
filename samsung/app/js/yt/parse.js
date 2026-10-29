// InnerTube JSON → plain items. A port of YouPipe's lib/innertube/parsers.dart (docs/innertube.md).
//
// youtube.com is midway through moving from *Renderer items to *ViewModel ones, and a response can mix both, so the
// walkers understand both families and collect items wherever they sit in the tree.
//
// Items:
//   video    {type, id, title, channel, channelId, avatar, thumb, duration, views, published, live, short}
//   channel  {type, id, name, avatar, subs}
//   playlist {type, id, title, thumb, channel, count}
// Feed entries: {kind: 'item', item} or {kind: 'shelf', title, items, shorts}.
var Parse = (function () {
  // Branches that never hold feed items: large chrome, and every kind of ad (YouPipe never shows ads).
  var SKIP = {
    frameworkUpdates: 1,
    topbar: 1,
    engagementPanels: 1,
    overlay: 1,
    microformat: 1,
    playerOverlays: 1,
    menu: 1,
    sheetViewModel: 1,
    adSlotRenderer: 1,
    promotedSparklesWebRenderer: 1,
    promotedVideoRenderer: 1,
    searchPyvRenderer: 1,
    statementBannerRenderer: 1,
    brandVideoShelfRenderer: 1,
    brandVideoSingletonRenderer: 1,
  };

  var SHELVES = { gridShelfViewModel: 1, reelShelfRenderer: 1, shelfRenderer: 1, richShelfRenderer: 1, horizontalCardListRenderer: 1 };

  // Helpers -----------------------------------------------------------------------------------------------------

  /** Follows [path] through nested objects/arrays; undefined as soon as a segment is missing. */
  function nav(root, path) {
    var cur = root;
    for (var i = 0; i < path.length; i++) {
      if (cur == null || typeof cur !== 'object') return undefined;
      cur = cur[path[i]];
    }
    return cur;
  }

  function list(root, path) {
    var v = nav(root, path);
    return Array.isArray(v) ? v.filter((x) => x && typeof x === 'object') : [];
  }

  /** The text of {simpleText} or {runs: [{text}]}, or {content} (view models). */
  function text(t) {
    if (!t || typeof t !== 'object') return null;
    if (typeof t.simpleText === 'string') return t.simpleText;
    if (typeof t.content === 'string') return t.content;
    if (!Array.isArray(t.runs)) return null;
    return t.runs.map((r) => (r && r.text) || '').join('');
  }

  function https(url) {
    return url ? (url.indexOf('//') === 0 ? 'https:' + url : url) : null;
  }

  /** The largest of {thumbnails: [{url, width}]} or {sources: [{url, width}]}. */
  function bestImage(node) {
    var l = list(node, ['thumbnails']);
    if (!l.length) l = list(node, ['sources']);
    if (!l.length) return null;
    var best = l.reduce((a, b) => ((a.width || 0) >= (b.width || 0) ? a : b));
    return https(best.url);
  }

  /** The first channel id (UC…) a browseEndpoint under [node] points to. */
  function channelIdIn(node) {
    if (Array.isArray(node)) {
      for (var i = 0; i < node.length; i++) {
        var f = channelIdIn(node[i]);
        if (f) return f;
      }
    } else if (node && typeof node === 'object') {
      var id = nav(node, ['browseEndpoint', 'browseId']);
      if (typeof id === 'string' && id.indexOf('UC') === 0) return id;
      for (var k in node) {
        var found = channelIdIn(node[k]);
        if (found) return found;
      }
    }
    return null;
  }

  /** The first avatarViewModel picture under [node]. */
  function findAvatar(node) {
    if (Array.isArray(node)) {
      for (var i = 0; i < node.length; i++) {
        var f = findAvatar(node[i]);
        if (f) return f;
      }
    } else if (node && typeof node === 'object') {
      if (node.avatarViewModel) return bestImage(node.avatarViewModel.image);
      for (var k in node) {
        var found = findAvatar(node[k]);
        if (found) return found;
      }
    }
    return null;
  }

  var SHORT_UNITS = { y: 'year', mo: 'month', w: 'week', d: 'day', h: 'hour', min: 'minute', m: 'minute', s: 'second' };

  /** YouTube's short ages ("3mo ago") in the long form ("3 months ago"). */
  function longAge(t) {
    return t.replace(/\b(\d+)\s?(mo|y|w|d|h|min|m|s) ago\b/g, (m, n, u) => n + ' ' + SHORT_UNITS[u] + (n === '1' ? '' : 's') + ' ago');
  }

  var VIEWS = /\b(views?|watching|No views)\b/i;
  var BARE_COUNT = /^[\d.,]+[KMB]?$/;
  var AGE = /\b(ago|Streamed|Premiered|Scheduled)\b/i;
  var PLAYLIST_LABEL = /^(Playlist|Podcast|Mix|Course|View full playlist|Updated .*)$/i;
  var DURATION = /^\d+(:\d\d)+$/;

  // Items --------------------------------------------------------------------------------------------------------

  function video(v) {
    var id = v.videoId;
    var title = text(v.title) || text(v.headline);
    if (!id || !title) return null;
    var byline = v.longBylineText || v.ownerText || v.shortBylineText;
    var length = text(v.lengthText);
    var views = text(v.shortViewCountText) || text(v.viewCountText);
    var liveBadge = list(v, ['badges']).some((b) => nav(b, ['metadataBadgeRenderer', 'style']) === 'BADGE_STYLE_TYPE_LIVE_NOW');
    // Playlist rows put "views • age" in videoInfo.
    var info = (nav(v, ['videoInfo', 'runs']) || []).map((r) => r.text || '').filter((t) => t.trim().length > 1);
    return {
      type: 'video',
      id: id,
      title: title,
      channel: text(byline),
      channelId: channelIdIn(byline),
      avatar: bestImage(
        nav(v, ['channelThumbnailSupportedRenderers', 'channelThumbnailWithLinkRenderer', 'thumbnail']) || v.channelThumbnail,
      ),
      thumb: bestImage(v.thumbnail) || thumbOf(id),
      duration: length,
      views: views || info[0] || null,
      published: text(v.publishedTimeText) || (info.length > 1 ? info[info.length - 1] : null),
      live: !length && ((views || '').indexOf('watching') >= 0 || liveBadge),
      short: false,
    };
  }

  function badgeTexts(thumbnailViewModel) {
    var out = [];
    list(thumbnailViewModel, ['overlays']).forEach((o) => {
      list(o, ['thumbnailBottomOverlayViewModel', 'badges'])
        .concat(list(o, ['thumbnailOverlayBadgeViewModel', 'thumbnailBadges']))
        .forEach((b) => {
          var t = nav(b, ['thumbnailBadgeViewModel', 'text']);
          if (t) out.push(t);
        });
    });
    return out;
  }

  function lockup(v) {
    var id = v.contentId;
    var meta = nav(v, ['metadata', 'lockupMetadataViewModel']);
    var title = nav(meta, ['title', 'content']);
    if (!id || !title) return null;
    var parts = [];
    list(meta, ['metadata', 'contentMetadataViewModel', 'metadataRows']).forEach((r) =>
      list(r, ['metadataParts']).forEach((p) => {
        var t = nav(p, ['text', 'content']);
        if (t) parts.push(t);
      }),
    );
    var type = v.contentType;
    if (type === 'LOCKUP_CONTENT_TYPE_PLAYLIST' || type === 'LOCKUP_CONTENT_TYPE_PODCAST' || type === 'LOCKUP_CONTENT_TYPE_SHOW') {
      var pimage = nav(v, ['contentImage', 'collectionThumbnailViewModel', 'primaryThumbnail', 'thumbnailViewModel']);
      return {
        type: 'playlist',
        id: id,
        title: title,
        thumb: bestImage(nav(pimage, ['image'])),
        // A channel's own playlists have only labels ("Playlist", "View full playlist"), no owner.
        channel: parts.filter((t) => !PLAYLIST_LABEL.test(t))[0] || null,
        count: badgeTexts(pimage)[0] || null,
      };
    }
    if (type && type !== 'LOCKUP_CONTENT_TYPE_VIDEO') return null;
    var image = nav(v, ['contentImage', 'thumbnailViewModel']);
    var badges = badgeTexts(image);
    var duration = badges.filter((b) => DURATION.test(b))[0] || null;
    // The rows' layout varies between experiments, so each part is classified by what it says.
    var channel = null;
    var views = null;
    var age = null;
    parts.forEach((p) => {
      var t = p.trim();
      if (!t || t[0] === '#') return;
      if (!views && VIEWS.test(t)) views = t;
      else if (!views && BARE_COUNT.test(t)) views = t + ' views';
      else if (!age && AGE.test(t)) age = longAge(t);
      else if (!channel) channel = t;
    });
    return {
      type: 'video',
      id: id,
      title: title,
      channel: channel,
      channelId: channelIdIn(meta),
      avatar: findAvatar(meta),
      thumb: bestImage(nav(image, ['image'])) || thumbOf(id),
      duration: duration,
      views: views,
      published: age,
      live: !duration && badges.some((b) => b.toUpperCase() === 'LIVE'),
      short: false,
    };
  }

  function shortsLockup(v) {
    var reel = nav(v, ['onTap', 'innertubeCommand', 'reelWatchEndpoint']);
    var id = nav(reel, ['videoId']);
    if (!id) return null;
    return {
      type: 'video',
      id: id,
      title: nav(v, ['overlayMetadata', 'primaryText', 'content']) || '',
      views: nav(v, ['overlayMetadata', 'secondaryText', 'content']) || null,
      thumb: bestImage(v.thumbnail) || bestImage(nav(reel, ['thumbnail'])) || thumbOf(id),
      short: true,
      live: false,
    };
  }

  function reelItem(v) {
    if (!v.videoId) return null;
    return {
      type: 'video',
      id: v.videoId,
      title: text(v.headline) || '',
      views: text(v.viewCountText),
      thumb: bestImage(v.thumbnail) || thumbOf(v.videoId),
      short: true,
      live: false,
    };
  }

  function channel(v) {
    var name = text(v.title);
    if (!v.channelId || !name) return null;
    // YouTube puts the @handle in subscriberCountText and the subscriber count in videoCountText.
    return {
      type: 'channel',
      id: v.channelId,
      name: name,
      avatar: bestImage(v.thumbnail),
      subs: [text(v.subscriberCountText), text(v.videoCountText)].filter(Boolean).join(' • '),
    };
  }

  function playlist(v) {
    var title = text(v.title);
    if (!v.playlistId || !title) return null;
    return {
      type: 'playlist',
      id: v.playlistId,
      title: title,
      thumb: bestImage(list(v, ['thumbnails'])[0]) || bestImage(v.thumbnail),
      channel: text(v.longBylineText || v.shortBylineText),
      count: v.videoCount || text(v.videoCountText),
    };
  }

  var PARSERS = {
    videoRenderer: video,
    gridVideoRenderer: video,
    compactVideoRenderer: video,
    channelVideoPlayerRenderer: video,
    playlistVideoRenderer: video,
    playlistPanelVideoRenderer: video,
    lockupViewModel: lockup,
    shortsLockupViewModel: shortsLockup,
    reelItemRenderer: reelItem,
    channelRenderer: channel,
    gridChannelRenderer: channel,
    playlistRenderer: playlist,
    gridPlaylistRenderer: playlist,
  };

  function thumbOf(id) {
    return 'https://i.ytimg.com/vi/' + id + '/hqdefault.jpg';
  }

  function key(item) {
    return item.type + ':' + item.id;
  }

  /** Every video, Short, channel and playlist under [root], in document order, without duplicates. */
  function items(root, seen) {
    seen = seen || {};
    var out = [];
    (function walk(o) {
      if (Array.isArray(o)) o.forEach(walk);
      else if (o && typeof o === 'object') {
        for (var k in o) {
          var parser = PARSERS[k];
          if (parser) {
            var item = o[k] && typeof o[k] === 'object' ? parser(o[k]) : null;
            if (item && !seen[key(item)]) {
              seen[key(item)] = 1;
              out.push(item);
            }
            continue;
          }
          if (!SKIP[k]) walk(o[k]);
        }
      }
    })(root);
    return out;
  }

  function shelfTitle(s) {
    return nav(s, ['header', 'sectionHeaderViewModel', 'headline', 'content']) || text(s.title) || text(nav(s, ['header', 'richListHeaderRenderer', 'title']));
  }

  /** Items and shelves under [root], in document order. Items already seen in an earlier entry are dropped. */
  function feed(root) {
    var out = [];
    var seen = {};
    (function walk(o) {
      if (Array.isArray(o)) o.forEach(walk);
      else if (o && typeof o === 'object') {
        for (var k in o) {
          var v = o[k];
          if (k === 'officialCardViewModel' && v && typeof v === 'object') {
            // Searching a channel's name: its card, then a row of its videos.
            var ch = officialCard(v);
            if (ch && !seen[key(ch)]) {
              seen[key(ch)] = 1;
              out.push({ kind: 'item', item: ch });
            }
            var its = items(v.contents, seen);
            if (its.length) out.push({ kind: 'shelf', title: '', items: its, shorts: false });
            continue;
          }
          if (SHELVES[k] && v && typeof v === 'object') {
            var shelfItems = items(v, seen);
            if (shelfItems.length) {
              var shorts = shelfItems.every((i) => i.short);
              out.push({ kind: 'shelf', title: shelfTitle(v) || (shorts ? 'Shorts' : ''), items: shelfItems, shorts: shorts });
            }
            continue;
          }
          var parser = PARSERS[k];
          if (parser) {
            var item = v && typeof v === 'object' ? parser(v) : null;
            if (item && !seen[key(item)]) {
              seen[key(item)] = 1;
              out.push({ kind: 'item', item: item });
            }
            continue;
          }
          if (!SKIP[k]) walk(v);
        }
      }
    })(root);
    return out;
  }

  /** Every item of [entries], shelves flattened. */
  function flatten(entries) {
    var out = [];
    entries.forEach((e) => (e.kind === 'item' ? out.push(e.item) : out.push.apply(out, e.items)));
    return out;
  }

  /** The token of the first continuation item under [root] (the "load more" at the end of a list). */
  function continuation(root) {
    var found = null;
    (function walk(o) {
      if (found) return;
      if (Array.isArray(o)) o.forEach(walk);
      else if (o && typeof o === 'object') {
        var c = o.continuationItemRenderer;
        if (c) {
          found = nav(c, ['continuationEndpoint', 'continuationCommand', 'token']) || nav(c, ['button', 'buttonRenderer', 'command', 'continuationCommand', 'token']);
          if (found) return;
        }
        var vm = o.continuationItemViewModel;
        if (vm) {
          found = nav(vm, ['continuationCommand', 'innertubeCommand', 'continuationCommand', 'token']);
          if (found) return;
        }
        for (var k in o) if (!SKIP[k]) walk(o[k]);
      }
    })(root);
    return found;
  }

  function metadataParts(viewModel) {
    var out = [];
    list(viewModel, ['metadata', 'contentMetadataViewModel', 'metadataRows']).forEach((r) =>
      list(r, ['metadataParts']).forEach((p) => {
        var t = nav(p, ['text', 'content']);
        if (t) out.push(t);
      }),
    );
    return out;
  }

  function officialCard(v) {
    var header = nav(v, ['header', 'pageHeaderViewModel']);
    var name = nav(header, ['title', 'dynamicTextViewModel', 'text', 'content']);
    var id = channelIdIn(header);
    if (!name || !id) return null;
    return {
      type: 'channel',
      id: id,
      name: name,
      avatar: bestImage(nav(header, ['image', 'contentPreviewImageViewModel', 'image'])),
      subs: metadataParts(header)
        .filter((p) => p.indexOf('video') < 0)
        .join(' • '),
    };
  }

  // Pages ---------------------------------------------------------------------------------------------------------

  /** The root holding a continuation's items. Some continuations (playlists) repeat an empty `contents` too. */
  function continuationRoot(data) {
    return data.onResponseReceivedActions || data.onResponseReceivedCommands || data.onResponseReceivedEndpoints || data.continuationContents || data.contents;
  }

  /** Any response (search, browse or next continuation) as entries and the next token. */
  function page(data) {
    var root = continuationRoot(data);
    return { entries: feed(root), continuation: continuation(root) };
  }

  function search(data) {
    var root = data.contents || continuationRoot(data);
    return { entries: feed(root), continuation: continuation(root) };
  }

  function sortChips(root) {
    var chips = [];
    (function walk(o) {
      if (Array.isArray(o)) o.forEach(walk);
      else if (o && typeof o === 'object') {
        var c = o.chipViewModel;
        if (c) {
          chips.push({
            label: c.text || '',
            token: nav(c, ['tapCommand', 'innertubeCommand', 'continuationCommand', 'token']) || null,
            selected: c.selected === true,
          });
          return;
        }
        for (var k in o) if (k !== 'contents' && k !== 'items') walk(o[k]);
      }
    })(root);
    return chips;
  }

  function channelPage(data, id) {
    var header = nav(data, ['header', 'pageHeaderRenderer']);
    var view = nav(header, ['content', 'pageHeaderViewModel']);
    var parts = metadataParts(view);
    var tabs = [];
    var selected = null;
    list(data, ['contents', 'twoColumnBrowseResultsRenderer', 'tabs']).forEach((t) => {
      var tab = t.tabRenderer;
      if (!tab || !tab.title) return;
      tabs.push({ title: tab.title, params: nav(tab, ['endpoint', 'browseEndpoint', 'params']) || null, selected: tab.selected === true });
      if (tab.selected) selected = tab.content;
    });
    return {
      id: id,
      name: (header && header.pageTitle) || nav(data, ['metadata', 'channelMetadataRenderer', 'title']) || '',
      avatar: bestImage(nav(view, ['image', 'decoratedAvatarViewModel', 'avatar', 'avatarViewModel', 'image'])),
      banner: bestImage(nav(view, ['banner', 'imageBannerViewModel', 'image'])),
      handle: parts.filter((p) => p[0] === '@')[0] || null,
      metadata: parts.filter((p) => p[0] !== '@'),
      description:
        nav(view, ['description', 'descriptionPreviewViewModel', 'description', 'content']) || nav(data, ['metadata', 'channelMetadataRenderer', 'description']) || '',
      tabs: tabs,
      sortChips: sortChips(selected),
      entries: feed(selected),
      continuation: continuation(selected),
    };
  }

  function playlistPage(data, id) {
    var header = nav(data, ['header', 'pageHeaderRenderer']);
    var view = nav(header, ['content', 'pageHeaderViewModel']);
    var owner = null;
    var ownerId = null;
    list(view, ['metadata', 'contentMetadataViewModel', 'metadataRows']).forEach((r) =>
      list(r, ['metadataParts']).forEach((p) => {
        var stack = nav(p, ['avatarStack', 'avatarStackViewModel', 'text']);
        if (stack) {
          owner = (stack.content || '').replace(/^by /, '');
          ownerId = channelIdIn(stack);
        }
      }),
    );
    var root = data.contents || continuationRoot(data);
    var videos = items(root).filter((i) => i.type === 'video');
    var next = continuation(root);
    // The account's own lists and some older playlists still use the older header.
    var old = nav(data, ['header', 'playlistHeaderRenderer']);
    if (!header && old) {
      return {
        id: id,
        title: text(old.title) || '',
        owner: text(old.ownerText),
        ownerId: channelIdIn(old.ownerText),
        thumb: bestImage(nav(old, ['playlistHeaderBanner', 'heroPlaylistThumbnailRenderer', 'thumbnail'])) || (videos[0] && videos[0].thumb),
        metadata: list(old, ['briefStats']).map(text).filter(Boolean),
        description: text(old.descriptionText) || '',
        videos: videos,
        continuation: next,
      };
    }
    return {
      id: id,
      title: (header && header.pageTitle) || '',
      owner: owner,
      ownerId: ownerId,
      thumb: bestImage(nav(view, ['heroImage', 'contentPreviewImageViewModel', 'image'])) || (videos[0] && videos[0].thumb),
      metadata: metadataParts(view),
      description: nav(view, ['description', 'descriptionPreviewViewModel', 'description', 'content']) || '',
      videos: videos,
      continuation: next,
    };
  }

  // Watch page (next) ---------------------------------------------------------------------------------------------

  function findKey(root, k) {
    var found = null;
    (function walk(o) {
      if (found) return;
      if (Array.isArray(o)) o.forEach(walk);
      else if (o && typeof o === 'object') {
        if (o[k] && typeof o[k] === 'object') {
          found = o[k];
          return;
        }
        for (var key in o) walk(o[key]);
      }
    })(root);
    return found;
  }

  function findAll(root, k) {
    var out = [];
    (function walk(o) {
      if (Array.isArray(o)) o.forEach(walk);
      else if (o && typeof o === 'object') {
        for (var key in o) {
          if (key === k) out.push(o[key]);
          else walk(o[key]);
        }
      }
    })(root);
    return out;
  }

  /** The watch page: details, channel, chapters, related videos and the comments token. */
  function watch(data) {
    var results = nav(data, ['contents', 'twoColumnWatchNextResults']);
    var primary = findKey(results && results.results, 'videoPrimaryInfoRenderer') || {};
    var secondary = findKey(results && results.results, 'videoSecondaryInfoRenderer') || {};
    var owner = nav(secondary, ['owner', 'videoOwnerRenderer']) || {};
    var likeVm = findKey(primary, 'likeButtonViewModel');
    var likes = likeVm ? JSON.stringify(likeVm).match(/"title":"([^"]+)"/) : null;
    var chapters = findAll(data.engagementPanels, 'macroMarkersListItemRenderer')
      .map((m) => ({
        title: text(m.title) || '',
        start: nav(m, ['onTap', 'watchEndpoint', 'startTimeSeconds']) ?? Format.parseTime(text(m.timeDescription)),
        thumb: bestImage(m.thumbnail),
      }))
      .filter((c) => c.start != null);
    // Chapters appear once per panel; key moments may repeat them.
    var seenStart = {};
    chapters = chapters.filter((c) => !seenStart[c.start] && (seenStart[c.start] = 1)).sort((a, b) => a.start - b.start);
    var commentsToken = null;
    list(results, ['results', 'results', 'contents']).forEach((s) => {
      var isr = s.itemSectionRenderer;
      if (isr && isr.sectionIdentifier === 'comment-item-section') commentsToken = continuation(isr);
    });
    var secondaryResults = results && results.secondaryResults;
    return {
      title: text(primary.title) || '',
      views: text(nav(primary, ['viewCount', 'videoViewCountRenderer', 'viewCount'])) || '',
      viewsShort: text(nav(primary, ['viewCount', 'videoViewCountRenderer', 'shortViewCount'])) || '',
      date: text(primary.dateText) || '',
      relativeDate: text(primary.relativeDateText) || '',
      likes: likes ? likes[1] : '',
      channel: {
        type: 'channel',
        id: channelIdIn(owner.navigationEndpoint) || channelIdIn(owner.title),
        name: text(owner.title) || '',
        avatar: bestImage(owner.thumbnail),
        subs: text(owner.subscriberCountText) || '',
      },
      description: nav(secondary, ['attributedDescription', 'content']) || '',
      chapters: chapters,
      related: items(secondaryResults).filter((i) => i.type === 'video' || i.type === 'playlist'),
      relatedContinuation: continuation(secondaryResults),
      commentsToken: commentsToken,
    };
  }

  // Comments ------------------------------------------------------------------------------------------------------

  /** A comments (or replies) continuation. Threads only hold keys; the data is in frameworkUpdates entities. */
  function comments(data) {
    var entities = {};
    list(data, ['frameworkUpdates', 'entityBatchUpdate', 'mutations']).forEach((m) => {
      var payload = m.payload;
      if (!payload || !m.entityKey) return;
      var k = Object.keys(payload)[0];
      if (k) entities[m.entityKey] = payload[k];
    });
    var out = [];
    var next = null;
    var count = null;
    function item(it) {
      var header = it.commentsHeaderRenderer;
      if (header) {
        var runs = nav(header, ['countText', 'runs']) || [];
        count = runs[0] ? runs[0].text : null;
        return;
      }
      var thread = it.commentThreadRenderer;
      var vm = nav(thread || it, ['commentViewModel', 'commentViewModel']) || it.commentViewModel;
      if (vm) {
        var entity = entities[vm.commentKey];
        if (!entity) return;
        var author = entity.author || {};
        var props = entity.properties || {};
        var replies = nav(thread, ['replies', 'commentRepliesRenderer']);
        out.push({
          id: props.commentId || '',
          text: nav(props, ['content', 'content']) || '',
          author: author.displayName || '',
          avatar: author.avatarThumbnailUrl || null,
          published: props.publishedTime || '',
          likes: nav(entity, ['toolbar', 'likeCountNotliked']) || '',
          replyCount: parseInt((nav(entity, ['toolbar', 'replyCount']) || '0').replace(/,/g, ''), 10) || 0,
          repliesToken: replies ? continuation(replies) : null,
          pinned: vm.pinnedText || null,
          creator: !!author.isCreator,
        });
        return;
      }
      var cont = it.continuationItemRenderer;
      if (cont) {
        next = nav(cont, ['continuationEndpoint', 'continuationCommand', 'token']) || nav(cont, ['button', 'buttonRenderer', 'command', 'continuationCommand', 'token']) || null;
      }
    }
    list(data, ['onResponseReceivedEndpoints']).forEach((e) => {
      ['reloadContinuationItemsCommand', 'appendContinuationItemsAction'].forEach((k) => list(e, [k, 'continuationItems']).forEach(item));
    });
    return { comments: out, continuation: next, count: count };
  }

  return {
    nav: nav,
    text: text,
    bestImage: bestImage,
    longAge: longAge,
    thumbOf: thumbOf,
    items: items,
    feed: feed,
    flatten: flatten,
    continuation: continuation,
    page: page,
    search: search,
    channelPage: channelPage,
    playlistPage: playlistPage,
    watch: watch,
    comments: comments,
  };
})();

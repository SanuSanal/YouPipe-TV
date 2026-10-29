// Video, channel and playlist cards, and the two ways they're laid out: rows that slide sideways (Home, Library,
// a channel's Home tab) and grids (Subscriptions, search results, a channel's Videos tab).
// OK opens a card; holding OK opens its options, like YouTube on TV.
var Cards = (function () {
  var h = Dom.h;
  var progressCache = null;

  Library.onChange((what) => {
    if (what === 'history') progressCache = null;
  });

  function progressOf(id) {
    if (!progressCache) {
      progressCache = {};
      Library.history().forEach((e) => {
        if (e.duration > 0) progressCache[e.video.id] = e.position / e.duration;
      });
    }
    return progressCache[id] || 0;
  }

  function video(item, opts) {
    var badge = item.live ? h('span.badge.live', { text: 'LIVE' }) : item.duration ? h('span.badge', { text: item.duration }) : null;
    var p = item.progress != null ? item.progress : progressOf(item.id);
    var meta2 = [item.views, item.published].filter(Boolean).join(' • ');
    var card = h('div.card.video-card.focusable' + (item.short ? '.short' : ''), [
      h('div.thumb', [Dom.img(item.thumb || Parse.thumbOf(item.id)), badge, p > 0.02 ? h('div.progress', [h('div', { style: { width: Math.min(100, p * 100) + '%' } })]) : null]),
      h('div.card-text', [h('div.card-title', { text: item.title }), h('div.card-meta', { text: item.channel || '' }), meta2 ? h('div.card-meta', { text: meta2 }) : null]),
    ]);
    card._item = item;
    card._activate = () => (opts && opts.play ? opts.play(item) : Watch.open(item));
    card._options = () => videoOptions(item, opts);
    card.addEventListener('click', card._activate);
    return card;
  }

  function channel(item) {
    var card = h('div.card.channel-card.focusable', [
      h('div.avatar-wrap', [Dom.img(item.avatar, 'avatar')]),
      h('div.card-text', [h('div.card-title', { text: item.name }), item.subs ? h('div.card-meta', { text: item.subs }) : null]),
    ]);
    card._item = item;
    card._activate = () => ChannelScreen.open(item);
    card._options = () => channelOptions(item);
    card.addEventListener('click', card._activate);
    return card;
  }

  function playlist(item) {
    var card = h('div.card.playlist-card.focusable', [
      h('div.thumb', [Dom.img(item.thumb), h('div.playlist-overlay', [Dom.icon('playlistPlay'), h('span', { text: item.count || '' })])]),
      h('div.card-text', [h('div.card-title', { text: item.title }), h('div.card-meta', { text: item.channel || 'Playlist' })]),
    ]);
    card._item = item;
    card._activate = () => PlaylistScreen.open(item);
    card._options = () => playlistOptions(item);
    card.addEventListener('click', card._activate);
    return card;
  }

  function of(item, opts) {
    return item.type === 'channel' ? channel(item) : item.type === 'playlist' ? playlist(item) : video(item, opts);
  }

  // Options (hold OK) -----------------------------------------------------------------------------------------------

  function videoOptions(item, opts) {
    var saved = Library.has('watchLater', item.id);
    var items = [
      { label: 'Play', icon: 'play', onSelect: () => Watch.open(item) },
      {
        label: saved ? 'Remove from Watch later' : 'Save to Watch later',
        icon: 'watchLater',
        onSelect: () => Overlay.toast(Library.toggle('watchLater', item) ? 'Saved to Watch later' : 'Removed from Watch later'),
      },
    ];
    if (item.channelId) {
      items.push({ label: 'Go to channel', sub: item.channel, icon: 'account', onSelect: () => ChannelScreen.open({ id: item.channelId, name: item.channel }) });
    }
    var extra = opts && opts.extraOptions;
    (typeof extra === 'function' ? extra(item) : extra || []).forEach((o) => items.push(o));
    Overlay.panel({ title: item.title, subtitle: item.channel, items: items });
  }

  function channelOptions(item) {
    var subscribed = Library.isSubscribed(item.id);
    Overlay.panel({
      title: item.name,
      items: [
        { label: 'Open channel', icon: 'account', onSelect: () => ChannelScreen.open(item) },
        {
          label: subscribed ? 'Unsubscribe' : 'Subscribe',
          icon: 'bell',
          onSelect: () => Overlay.toast(Library.toggleSubscription(item) ? 'Subscribed to ' + item.name : 'Unsubscribed from ' + item.name),
        },
      ],
    });
  }

  function playlistOptions(item) {
    var saved = Library.has('playlists', item.id);
    Overlay.panel({
      title: item.title,
      items: [
        { label: 'Open playlist', icon: 'playlistPlay', onSelect: () => PlaylistScreen.open(item) },
        {
          label: saved ? 'Remove from Library' : 'Save to Library',
          icon: 'playlistAdd',
          onSelect: () => Overlay.toast(Library.toggle('playlists', item) ? 'Saved to Library' : 'Removed from Library'),
        },
      ],
    });
  }

  // Layouts --------------------------------------------------------------------------------------------------------

  /**
   * A titled row that slides sideways. opts: {title, more(): Promise<items>, cardOpts, empty}. Returns
   * {el, add(items), setStatus(text)}. more() is called when focus nears the end.
   */
  function row(opts) {
    var track = h('div.row-track.hscroll', { 'data-group': 'row' });
    var status = h('div.row-status');
    var el = h('section.row.vline', [h('div.row-title', { text: opts.title || '' }), h('div.row-viewport', [track, status])]);
    var loading = false;
    var exhausted = !opts.more;
    track._nearEnd = async () => {
      if (loading || exhausted) return;
      loading = true;
      try {
        var more = await opts.more();
        if (!more.length) exhausted = true;
        add(more);
      } catch (e) {
        exhausted = true;
        Log.add('row "' + opts.title + '" more failed: ' + e.message);
      } finally {
        loading = false;
      }
    };
    function add(items) {
      track.querySelectorAll('.placeholder').forEach((p) => p.remove());
      items.forEach((it) => {
        if (track.querySelector('[data-id="' + it.type + ':' + it.id + '"]')) return;
        var c = of(it, opts.cardOpts);
        c.dataset.id = it.type + ':' + it.id;
        track.appendChild(c);
      });
      status.textContent = track.children.length ? '' : opts.empty || '';
      el.classList.toggle('empty', !track.children.length);
    }
    function setStatus(text) {
      status.textContent = text || '';
    }
    /** Grey cards while the row loads. */
    function placeholders() {
      for (var i = 0; i < 5; i++) track.appendChild(h('div.card.placeholder', [h('div.thumb'), h('div.card-text', [h('div.ph-line'), h('div.ph-line.short')])]));
    }
    return { el: el, track: track, add: add, setStatus: setStatus, placeholders: placeholders };
  }

  /** A grid of cards, 4 across. opts: {more(), cardOpts, columns}. Returns {el, add(items), clear()}. */
  function grid(opts) {
    opts = opts || {};
    var el = h('div.grid' + (opts.columns ? '.cols-' + opts.columns : ''), { 'data-group': 'grid' });
    var loading = false;
    var exhausted = !opts.more;
    el._nearEnd = async () => {
      if (loading || exhausted) return;
      loading = true;
      try {
        var more = await opts.more();
        if (!more.length) exhausted = true;
        add(more);
      } catch (e) {
        exhausted = true;
        Log.add('grid more failed: ' + e.message);
      } finally {
        loading = false;
      }
    };
    function add(items) {
      items.forEach((it) => {
        if (el.querySelector('[data-id="' + it.type + ':' + it.id + '"]')) return;
        var c = of(it, opts.cardOpts);
        c.dataset.id = it.type + ':' + it.id;
        el.appendChild(c);
      });
    }
    return {
      el: el,
      add: add,
      clear: () => Dom.clear(el),
      setMore: (fn) => {
        opts.more = fn;
        exhausted = !fn;
      },
    };
  }

  // Load more when focus gets near the end of a row or grid.
  Focus.onChange((el) => {
    var c = el && el.parentElement;
    if (!c || !c._nearEnd) return;
    var cards = c.children;
    var i = Array.prototype.indexOf.call(cards, el);
    if (i >= cards.length - 8) c._nearEnd();
  });

  return { video: video, channel: channel, playlist: playlist, of: of, row: row, grid: grid, videoOptions: videoOptions };
})();

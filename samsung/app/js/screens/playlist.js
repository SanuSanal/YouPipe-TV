// A playlist: its details and Play all / Shuffle / Save on the left, the videos as a list on the right.
var PlaylistScreen = (function () {
  var h = Dom.h;

  function open(item) {
    var s = Screens.base('playlist', 24);
    var info = h('div.playlist-info');
    var list = h('div.playlist-list.vlist', { 'data-group': 'playlist' });
    var right = h('div.playlist-right', [h('div.playlist-viewport', [h('div.playlist-scroll.vscroll', { data: { mode: 'keep', pad: '24' } }, [list])])]);
    // The page itself doesn't scroll: the list does.
    s.content.classList.remove('vscroll');
    Dom.append(s.content, [h('div.playlist-layout', [info, right])]);
    s.firstFocus = () => info.querySelector('.focusable');
    Router.push(s);
    info.appendChild(h('div.loading-line', { text: 'Loading…' }));

    var videos = [];
    var token = null;
    var loading = false;

    async function more() {
      if (!token || loading) return [];
      loading = true;
      try {
        var p = await InnerTube.playlistMore(token);
        token = p.continuation;
        add(p.videos);
        return p.videos;
      } finally {
        loading = false;
      }
    }

    function queueFrom(index, shuffled) {
      var items = videos.slice();
      if (shuffled) {
        for (var i = items.length - 1; i > 0; i--) {
          var j = Math.floor(Math.random() * (i + 1));
          var t = items[i];
          items[i] = items[j];
          items[j] = t;
        }
      }
      return { items: items, index: shuffled ? 0 : index, title: item.title, more: shuffled ? null : more };
    }

    function add(items) {
      items.forEach((v) => {
        var i = videos.length;
        videos.push(v);
        var row = h('div.playlist-row.focusable', [
          h('div.playlist-index', { text: String(i + 1) }),
          h('div.thumb.small', [Dom.img(v.thumb), v.duration ? h('span.badge', { text: v.duration }) : null]),
          h('div.playlist-row-text', [h('div.card-title', { text: v.title }), h('div.card-meta', { text: [v.channel, v.views].filter(Boolean).join(' • ') })]),
        ]);
        row._item = v;
        row._activate = () => Watch.open(v, { queue: queueFrom(i) });
        row._options = () => Cards.videoOptions(v);
        row.addEventListener('click', row._activate);
        list.appendChild(row);
      });
    }
    list._nearEnd = more;

    function button(label, iconName, action) {
      var b = h('div.button.focusable', [Dom.icon(iconName), h('span', { text: label })]);
      b._activate = action;
      b.addEventListener('click', action);
      return b;
    }

    (async () => {
      try {
        var page = await InnerTube.playlist(item.id);
        token = page.continuation;
        add(page.videos);
        Dom.clear(info);
        var saveButton = button(Library.has('playlists', item.id) ? 'Saved' : 'Save', 'playlistAdd', () => {
          var saved = Library.toggle('playlists', { type: 'playlist', id: item.id, title: page.title || item.title, thumb: page.thumb || item.thumb, channel: page.owner || item.channel, count: item.count });
          saveButton.lastChild.textContent = saved ? 'Saved' : 'Save';
          Overlay.toast(saved ? 'Saved to Library' : 'Removed from Library');
        });
        Dom.append(info, [
          h('div.thumb.large', [Dom.img(page.thumb || item.thumb)]),
          h('div.playlist-title', { text: page.title || item.title }),
          h('div.playlist-owner', { text: page.owner || item.channel || '' }),
          h('div.playlist-meta', { text: page.metadata.filter((m) => m !== 'Playlist').join(' • ') }),
          h('div.playlist-buttons', { 'data-group': 'playlist-buttons' }, [
            button('Play all', 'play', () => videos.length && Watch.open(videos[0], { queue: queueFrom(0) })),
            button('Shuffle', 'shuffle', () => videos.length && Watch.open(null, { queue: queueFrom(0, true) })),
            saveButton,
          ]),
        ]);
        if (!videos.length) list.appendChild(Screens.message('This playlist is empty'));
        if (!s.el.hidden && !Overlay.isOpen()) Focus.set(s.firstFocus(), { instant: true });
      } catch (e) {
        Dom.clear(info);
        info.appendChild(Screens.message("Couldn't load this playlist", e.message));
        Log.add('playlist ' + item.id + ' failed: ' + e.message);
      }
    })();

    return s;
  }

  return { open: open };
})();

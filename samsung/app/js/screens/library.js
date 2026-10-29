// Subscriptions and Library: the user's own things, all kept on the TV.
var SubscriptionsScreen = (function () {
  var h = Dom.h;

  function create() {
    var s = Screens.base('subscriptions', 64);
    s.keep = true;
    var shownAt = 0;

    function render(videos) {
      var keepFocus = s.el.contains(Focus.current) ? Focus.current.dataset.id : null;
      Dom.clear(s.content);
      var subs = Library.subscriptions();
      if (!subs.length) {
        s.content.appendChild(
          Screens.message('No subscriptions yet', 'Open a channel and choose Subscribe. Its new videos show up here.', {
            label: 'Search',
            onSelect: () => Sidenav.go('search'),
          }),
        );
        return;
      }
      var channels = Cards.row({ title: 'Channels' });
      channels.add(subs);
      channels.el.classList.add('channels-row');
      var grid = Cards.grid();
      grid.add(videos);
      Dom.append(s.content, [channels.el, h('div.row-title.vline', { text: videos.length ? 'Latest videos' : 'Loading videos…' }), grid.el]);
      var again = keepFocus && s.content.querySelector('[data-id="' + keepFocus + '"]');
      if (again) Focus.set(again, { instant: true });
      else if (!Sidenav.contains(Focus.current) && !s.el.hidden && !Overlay.isOpen()) Router.focusScreen();
    }

    s.firstFocus = () => s.content.querySelector('.grid .focusable') || s.content.querySelector('.focusable');
    s.onShow = () => {
      render(SubsFeed.videos());
      if (Date.now() - shownAt < 60 * 1000) return;
      shownAt = Date.now();
      SubsFeed.refresh(false)
        .then((videos) => {
          if (!s.el.hidden) render(videos);
        })
        .catch((e) => Log.add('subscriptions refresh failed: ' + e.message));
    };
    return s;
  }

  return { create: create };
})();

// Library: the lists kept on the TV. Signed in, the account's YouTube history, Watch later, liked videos and playlists
// follow the TV's history (read from youtube.com, js/data/account.js).
var LibraryScreen = (function () {
  var ROW_LIMIT = 20;
  var ACCOUNT_ROWS = [
    ['YouTube history', () => Account.history()],
    ['YouTube Watch later', () => Account.playlist('WL')],
    ['YouTube liked videos', () => Account.playlist('LL')],
    ['YouTube playlists', () => Account.playlists()],
  ];
  // The account's pages are large (about 1 MB each), so a visit within two minutes reuses them.
  var accountCache = { at: 0, lists: {} };

  function create() {
    var s = Screens.base('library', 64);

    function section(title, items, opts) {
      var row = Cards.row({ title: title, cardOpts: opts && opts.cardOpts });
      row.add(items.slice(0, ROW_LIMIT));
      if (items.length > ROW_LIMIT || (opts && opts.alwaysAll)) {
        var all = Dom.h('div.card.see-all.focusable', [Dom.h('div.see-all-box', { text: 'See all' })]);
        all._activate = () => ListScreen.open(title, items, { cardOpts: opts && opts.cardOpts });
        all.addEventListener('click', all._activate);
        row.track.appendChild(all);
      }
      return row.el;
    }

    function render() {
      Dom.clear(s.content);
      var history = Library.history().map((e) => Object.assign({}, e.video, { progress: e.duration ? e.position / e.duration : 0 }));
      var sections = [
        ['History', history, 'history'],
        ['Watch later', Library.listOf('watchLater'), 'watchLater'],
        ['Liked videos', Library.listOf('liked'), 'liked'],
        ['Saved playlists', Library.listOf('playlists'), null],
        ['Subscriptions', Library.subscriptions(), null],
      ];
      var any = false;
      sections.forEach((sec, i) => {
        if (sec[1].length) {
          any = true;
          s.content.appendChild(section(sec[0], sec[1], sec[2] ? withRemove(sec[2], sec[0]) : null));
        }
        if (i === 0 && Account.signedIn()) {
          any = true;
          accountRows();
        }
      });
      if (!any) {
        s.content.appendChild(Screens.message('Your library is empty', 'Videos you watch, save for later or like, and playlists you save, show up here.'));
      }
    }

    /** The account's lists, each a row that fills in when its page arrives. */
    function accountRows() {
      if (Date.now() - accountCache.at > 2 * 60 * 1000) accountCache = { at: Date.now(), lists: {} };
      var tasks = ACCOUNT_ROWS.map((def) => {
        var title = def[0];
        var row = Cards.row({ title: title });
        s.content.appendChild(row.el);
        function fill(items) {
          if (!items.length) return row.el.remove();
          row.add(items.slice(0, ROW_LIMIT));
          if (items.length <= ROW_LIMIT) return;
          // The rest of the first page; youtube.com's page holds up to 100 videos.
          var all = Dom.h('div.card.see-all.focusable', [Dom.h('div.see-all-box', { text: 'See all' })]);
          all._activate = () => ListScreen.open(title, items);
          all.addEventListener('click', all._activate);
          row.track.appendChild(all);
        }
        var cached = accountCache.lists[title];
        if (cached) return fill(cached);
        row.placeholders();
        return async () => {
          try {
            var items = await def[1]();
            accountCache.lists[title] = items;
            if (row.el.isConnected) fill(items);
          } catch (e) {
            Log.add('account row "' + title + '" failed: ' + e.message);
            row.el.remove();
          }
        };
      });
      Screens.queue(tasks.filter(Boolean), 2);
    }

    /** Card options that add "Remove from <list>" for the list the card sits in. */
    function withRemove(key, title) {
      return {
        cardOpts: {
          extraOptions: (item) => [
            {
              label: 'Remove from ' + title,
              icon: 'close',
              onSelect: () => {
                Library.remove(key, item.id);
                render();
                Router.focusScreen();
              },
            },
          ],
        },
      };
    }

    s.firstFocus = () => s.content.querySelector('.focusable');
    s.onShow = render;
    return s;
  }

  return { create: create };
})();

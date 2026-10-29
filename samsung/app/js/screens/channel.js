// A channel: banner, avatar, Subscribe, then tabs (Home as rows; Videos, Live and Playlists as grids).
var ChannelScreen = (function () {
  var h = Dom.h;
  var TABS = ['Home', 'Videos', 'Live', 'Playlists', 'Podcasts'];

  function open(channel) {
    var s = Screens.base('channel', 48);
    var header = h('div.channel-header.vline.vtop');
    var tabs = h('div.tabs.vline.vtop', { 'data-group': 'tabs' });
    var body = h('div.channel-body');
    Dom.append(s.content, [header, tabs, body]);
    s.firstFocus = () => tabs.querySelector('.tab.active') || tabs.querySelector('.focusable') || body.querySelector('.focusable');
    Router.push(s);
    s.content.appendChild(Screens.message('Loading…'));
    load(null);

    function subscribeButton(page) {
      var b = h('div.button.focusable.subscribe');
      function label() {
        var on = Library.isSubscribed(page.id);
        b.textContent = on ? 'Subscribed' : 'Subscribe';
        b.classList.toggle('on', on);
      }
      b._activate = () => {
        var on = Library.toggleSubscription({ id: page.id, name: page.name, avatar: page.avatar });
        Overlay.toast(on ? 'Subscribed to ' + page.name : 'Unsubscribed from ' + page.name);
        label();
      };
      b.addEventListener('click', b._activate);
      label();
      return b;
    }

    function renderHeader(page) {
      Dom.clear(header);
      if (page.banner) header.style.backgroundImage = 'url("' + page.banner + '")';
      Dom.append(header, [
        h('div.channel-header-shade'),
        h('div.channel-header-row', [
          Dom.img(page.avatar || channel.avatar, 'channel-avatar'),
          h('div.channel-header-text', [
            h('div.channel-name', { text: page.name || channel.name || '' }),
            h('div.channel-meta', { text: [page.handle].concat(page.metadata).filter(Boolean).join(' • ') }),
            h('div.channel-buttons', [subscribeButton(page)]),
          ]),
        ]),
      ]);
    }

    function renderTabs(page) {
      Dom.clear(tabs);
      page.tabs
        .filter((t) => TABS.indexOf(t.title) >= 0)
        .forEach((t) => {
          var b = h('div.tab.focusable' + (t.selected ? '.active' : ''), { text: t.title });
          b._activate = () => {
            if (t.selected) return;
            load(t.params, t.title);
          };
          b.addEventListener('click', b._activate);
          tabs.appendChild(b);
          if (t.selected) tabs._last = b;
        });
    }

    function renderHome(page) {
      var loose = [];
      page.entries.forEach((e) => {
        if (e.kind === 'item') return loose.push(e.item);
        if (e.shorts) return;
        var row = Cards.row({ title: e.title });
        row.add(e.items);
        body.appendChild(row.el);
      });
      if (loose.length) {
        var row = Cards.row({ title: 'Featured' });
        row.add(loose.filter((i) => !i.short));
        body.insertBefore(row.el, body.firstChild);
      }
    }

    function renderGrid(page) {
      var token = page.continuation;
      if (page.sortChips.length) {
        var chips = h('div.chips.vline', { 'data-group': 'chips' });
        page.sortChips.forEach((c) => {
          var b = h('div.chip.focusable' + (c.selected ? '.active' : ''), { text: c.label });
          b._activate = async () => {
            if (!c.token || c.selected) return;
            page.sortChips.forEach((x) => (x.selected = x === c));
            chips.querySelectorAll('.chip').forEach((x) => x.classList.toggle('active', x === b));
            var p = await InnerTube.browseMore(c.token);
            token = p.continuation;
            grid.clear();
            grid.add(Parse.flatten(p.entries).filter((i) => !i.short));
          };
          b.addEventListener('click', b._activate);
          chips.appendChild(b);
        });
        body.appendChild(chips);
      }
      var grid = Cards.grid({
        more: async () => {
          if (!token) return [];
          var p = await InnerTube.browseMore(token);
          token = p.continuation;
          return Parse.flatten(p.entries).filter((i) => !i.short);
        },
      });
      var items = Parse.flatten(page.entries).filter((i) => !i.short);
      grid.add(items);
      body.appendChild(items.length ? grid.el : Screens.message('Nothing here'));
    }

    async function load(params, title) {
      var fromTab = tabs.contains(Focus.current);
      Dom.clear(body);
      body.appendChild(h('div.loading-line', { text: 'Loading…' }));
      try {
        var page = await InnerTube.channel(channel.id, params);
        var msg = s.content.querySelector('.message');
        if (msg && !body.contains(msg)) msg.remove();
        if (!header.firstChild) renderHeader(page);
        renderTabs(page);
        Dom.clear(body);
        var selected = (page.tabs.filter((t) => t.selected)[0] || {}).title || title || 'Home';
        if (selected === 'Home') renderHome(page);
        else renderGrid(page);
        // First load: focus the tabs. Switching tabs keeps focus on the tab that was chosen.
        var f = Focus.current;
        if (!s.el.hidden && !Overlay.isOpen() && (fromTab || !f || !f.isConnected || !s.el.contains(f))) {
          Focus.set(s.firstFocus(), { instant: true });
        }
      } catch (e) {
        Dom.clear(body);
        body.appendChild(Screens.message("Couldn't load this channel", e.message, { label: 'Try again', onSelect: () => load(params, title) }));
        Log.add('channel ' + channel.id + ' failed: ' + e.message);
        if (!s.el.hidden) Router.focusScreen();
      }
    }

    return s;
  }

  return { open: open };
})();

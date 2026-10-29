// Home: rows of videos that slide sideways (data/home.js says where each row comes from).
var HomeScreen = (function () {
  function create() {
    var s = Screens.base('home', 64);
    Topbar.attach(s);
    s.keep = true;
    var builtAt = 0;
    var keysAtBuild = 0;
    var cwRow = null;
    var historyChanged = false;

    Library.onChange((what) => {
      if (what === 'history') historyChanged = true;
    });

    function build() {
      Dom.clear(s.content);
      builtAt = Date.now();
      keysAtBuild = App.keyCount;
      historyChanged = false;
      cwRow = null;
      var tasks = Home.sources().map((src) => {
        var row = Cards.row({ title: src.title, more: src.more });
        row.placeholders();
        if (src.title === 'Continue watching') cwRow = row;
        s.content.appendChild(row.el);
        return async () => {
          try {
            var items = await src.load();
            row.add(items);
            if (!items.length) row.el.remove();
            else maybeFocus();
          } catch (e) {
            Log.add('home row "' + src.title + '" failed: ' + e.message);
            row.el.remove();
          }
        };
      });
      Screens.queue(tasks, 3).then(() => {
        if (!s.content.querySelector('.card')) {
          s.content.appendChild(
            Screens.message("Couldn't load Home", 'Check the TV is online, then try again.', { label: 'Try again', onSelect: build }),
          );
          maybeFocus();
        }
      });
    }

    /**
     * Focuses the first card of the first row that has loaded. Until the user presses a key, a row above the
     * focused one that loads later takes the focus, so Home always starts at its top row.
     */
    function maybeFocus() {
      if (s.el.hidden || Overlay.isOpen()) return;
      var f = Focus.current;
      var untouched = App.keyCount === keysAtBuild;
      if (!untouched && f && f.isConnected && (s.el.contains(f) || Sidenav.contains(f) || Topbar.contains(f))) return;
      var first = s.content.querySelector('.focusable');
      if (first && first !== f) Focus.set(first, { instant: true });
    }

    s.firstFocus = () => s.content.querySelector('.focusable');
    s.onShow = () => {
      if (!builtAt || Date.now() - builtAt > 60 * 60 * 1000) return build();
      // Coming back from a video: refresh Continue watching unless focus is in it.
      if (historyChanged) {
        historyChanged = false;
        var cw = Library.continueWatching().slice(0, 30);
        var focusInCw = cwRow && cwRow.el.contains(s.lastFocus);
        if (cwRow && !focusInCw) {
          Dom.clear(cwRow.track);
          cwRow.add(cw);
          if (!cw.length) cwRow.el.remove();
        } else if (!cwRow && cw.length) {
          cwRow = Cards.row({ title: 'Continue watching' });
          cwRow.add(cw);
          s.content.insertBefore(cwRow.el, s.content.firstChild);
        }
      }
    };
    s.refresh = build;
    return s;
  }

  return { create: create };
})();

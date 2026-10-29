// Search, like YouTube on TV: the keyboard on the left; suggestions (or recent searches) on the right while typing,
// and the results there after a search.
var SearchScreen = (function () {
  var h = Dom.h;

  function create() {
    var s = Screens.base('search', 0);
    s.keep = true;
    var suggestTimer = null;
    var suggestSeq = 0;
    // The keyboard stays put; only the right side (suggestions, results) slides.
    s.content.classList.remove('vscroll');
    var right = h('div.search-right-scroll.vscroll', { data: { pad: '72' } });
    var kb = Keyboard.create({ onChange: onChange, onSubmit: run });
    Dom.append(s.content, [h('div.search-layout', [h('div.search-left', [kb.el]), h('div.search-right', [h('div.search-right-viewport', [right])])])]);

    function showList(title, entries) {
      Dom.clear(right);
      right._y = 0;
      right.style.transform = '';
      var list = h('div.suggestions.vlist', { 'data-group': 'suggestions' });
      entries.forEach((q) => {
        var row = h('div.suggestion.focusable', [Dom.icon(title === 'Recent searches' ? 'history' : 'search'), h('span', { text: q })]);
        row._activate = () => {
          kb.set(q);
          run(q);
        };
        row.addEventListener('click', row._activate);
        list.appendChild(row);
      });
      Dom.append(right, [h('div.search-heading', { text: entries.length ? title : '' }), list]);
    }

    function onChange(text) {
      clearTimeout(suggestTimer);
      var seq = ++suggestSeq;
      if (!text.trim()) return showList('Recent searches', Library.searches());
      suggestTimer = setTimeout(async () => {
        try {
          var list = await InnerTube.suggestions(text);
          if (seq === suggestSeq) showList('Suggestions', list.slice(0, 10));
        } catch (e) {
          Log.add('suggestions failed: ' + e.message);
        }
      }, 250);
    }

    async function run(query) {
      query = (query || '').trim();
      if (!query) return;
      clearTimeout(suggestTimer);
      suggestSeq++;
      Library.addSearch(query);
      Dom.clear(right);
      right._y = 0;
      right.style.transform = '';
      var status = h('div.search-heading', { text: 'Searching for “' + query + '”…' });
      right.appendChild(status);
      try {
        var page = await InnerTube.search(query);
        var token = page.continuation;
        var items = Parse.flatten(page.entries).filter((i) => !i.short);
        status.textContent = items.length ? 'Results for “' + query + '”' : 'No results for “' + query + '”';
        var grid = Cards.grid({
          columns: 3,
          more: async () => {
            if (!token) return [];
            var p = await InnerTube.searchMore(token);
            token = p.continuation;
            return Parse.flatten(p.entries).filter((i) => !i.short);
          },
        });
        grid.add(items);
        right.appendChild(grid.el);
        // Focus moves to the results unless the user went elsewhere (the suggestion it was on is gone now).
        var first = grid.el.querySelector('.focusable');
        var f = Focus.current;
        if (first && (!f || !f.isConnected || right.contains(f))) Focus.set(first);
      } catch (e) {
        status.textContent = "Couldn't search: " + e.message;
      }
    }

    s.firstFocus = kb.firstKey;
    s.onKey = (e) => {
      // A real keyboard types into the box.
      if (e.key && e.key.length === 1 && !e.ctrlKey && !e.altKey && !e.metaKey) {
        kb.type(e.key);
        return true;
      }
      if (e.keyCode === Platform.KEY.BACKSPACE) {
        kb.backspace();
        return true;
      }
      return false;
    };
    s.onBack = () => {
      // From the results, Back returns to the keyboard first.
      if (right.contains(Focus.current)) {
        Focus.set(kb.firstKey());
        return true;
      }
      return false;
    };
    s.search = (q) => {
      kb.set(q);
      run(q);
    };
    return s;
  }

  return { create: create };
})();

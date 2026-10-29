// Shared screen scaffolding: a screen element whose content slides up and down with focus (.vscroll).
var Screens = (function () {
  var h = Dom.h;

  /** {el, content}: content is the sliding page; pad is the space kept above the focused row. */
  function base(name, pad) {
    var content = h('div.screen-content.vscroll', { data: { pad: String(pad == null ? 48 : pad) } });
    var el = h('section.screen.screen-' + name, [h('div.screen-viewport', [content])]);
    return { el: el, content: content };
  }

  /** A message with an optional button, for empty and error states. */
  function message(title, detail, button) {
    var b = null;
    if (button) {
      b = h('div.button.focusable', { text: button.label });
      b._activate = button.onSelect;
      b.addEventListener('click', button.onSelect);
    }
    return h('div.message.vline', [h('div.message-title', { text: title }), detail ? h('div.message-detail', { text: detail }) : null, b]);
  }

  /** Runs async loaders a few at a time, in order. */
  function queue(tasks, concurrency) {
    var next = 0;
    function worker() {
      if (next >= tasks.length) return Promise.resolve();
      var t = tasks[next++];
      return Promise.resolve()
        .then(t)
        .catch(() => {})
        .then(worker);
    }
    var workers = [];
    for (var i = 0; i < (concurrency || 3); i++) workers.push(worker());
    return Promise.all(workers);
  }

  return { base: base, message: message, queue: queue };
})();

/** A titled grid of items: "See all" lists, and lists with paging (opts.more). */
var ListScreen = (function () {
  var h = Dom.h;

  function open(title, items, opts) {
    opts = opts || {};
    var s = Screens.base('list', 140);
    var grid = Cards.grid({ more: opts.more, cardOpts: opts.cardOpts });
    Dom.append(s.content, [h('h1.page-title.vline', { text: title }), grid.el]);
    if (items.length) grid.add(items);
    else s.content.appendChild(Screens.message(opts.empty || 'Nothing here yet'));
    s.firstFocus = () => grid.el.querySelector('.focusable');
    Router.push(s);
    return s;
  }

  return { open: open };
})();

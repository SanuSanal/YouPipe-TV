// The left menu, like YouTube on TV: a rail of icons that opens with labels while it has focus.
var Sidenav = (function () {
  var ITEMS = [
    ['search', 'Search', 'search'],
    ['home', 'Home', 'home'],
    ['subscriptions', 'Subscriptions', 'subscriptions'],
    ['library', 'Library', 'library'],
    ['settings', 'Settings', 'settings'],
  ];
  var el = null;
  var buttons = {};
  var roots = {};
  var factories = {};

  function build(container) {
    el = container;
    var h = Dom.h;
    var list = h('div.nav-items.vlist', { 'data-group': 'nav' });
    ITEMS.forEach((it) => {
      var b = h('div.nav-item.focusable', { data: { nav: it[0] } }, [Dom.icon(it[2]), h('span.nav-label', { text: it[1] })]);
      b._activate = () => go(it[0]);
      b.addEventListener('click', () => go(it[0]));
      buttons[it[0]] = b;
      list.appendChild(b);
    });
    // Settings sits at the bottom, like YouTube's.
    list.lastChild.classList.add('nav-bottom');
    Dom.append(el, [h('div.nav-brand', [Dom.img('logo.svg', 'nav-logo'), h('span.nav-wordmark', { text: 'YouPipe' })]), list]);
    Focus.onChange((now) => document.getElementById('app').classList.toggle('nav-open', !!now && el.contains(now)));
  }

  /** Registers the factory for a section's root screen. */
  function register(key, factory) {
    factories[key] = factory;
  }

  /** Opens a section. Home and Subscriptions keep their screen between visits. */
  function go(key, opts) {
    var s = roots[key];
    if (!s || (opts && opts.fresh)) {
      if (s && s.destroy) s.destroy();
      if (s && s.el.parentNode) s.el.parentNode.removeChild(s.el);
      s = factories[key]();
      s.nav = key;
      if (s.keep) roots[key] = s;
    }
    Router.root(s);
  }

  /** Forgets a kept section, so the next visit builds it again. */
  function reset(key) {
    var s = roots[key];
    if (!s || Router.top() === s) return;
    if (s.destroy) s.destroy();
    if (s.el.parentNode) s.el.parentNode.removeChild(s.el);
    delete roots[key];
  }

  function setActive(key) {
    Object.keys(buttons).forEach((k) => buttons[k].classList.toggle('active', k === key));
    if (buttons[key]) buttons[key].parentNode._last = buttons[key];
  }

  /** Focuses the menu on the active section. */
  function enter() {
    var active = el.querySelector('.nav-item.active') || el.querySelector('.nav-item');
    Focus.set(active);
  }

  function contains(node) {
    return !!el && !!node && el.contains(node);
  }

  return { build: build, register: register, go: go, reset: reset, setActive: setActive, enter: enter, contains: contains };
})();

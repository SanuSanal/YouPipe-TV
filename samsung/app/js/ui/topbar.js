// The bar above Home, Subscriptions and Library, like YouTube on TV: the account at the top left, then a search box
// and the YouPipe name. Up from a screen's first row reaches it, and Up stops there. It scrolls away with the screen.
var Topbar = (function () {
  var SECTIONS = { home: 1, subscriptions: 1, library: 1 };
  // Where a screen's first row starts: below the bar (docs/ui.md).
  var TOP = 152;
  var el = null;
  var account = null;

  function build(container) {
    el = container;
    var h = Dom.h;
    account = h('div.topbar-account.focusable', { data: { label: 'account' } });
    account._activate = () => Sidenav.go('account');
    account.addEventListener('click', account._activate);
    var search = h('div.topbar-search.focusable', [Dom.icon('search'), h('span', { text: 'Search' })]);
    search._activate = () => Sidenav.go('search');
    search.addEventListener('click', search._activate);
    var bar = h('div.topbar-items', { 'data-group': 'topbar' }, [
      account,
      search,
      h('div.topbar-brand', [Dom.img('logo.svg', 'topbar-logo'), h('span', { text: 'YouPipe' })]),
    ]);
    el.appendChild(bar);
    showAccount();
    Account.onChange(showAccount);
    Focus.onChange(update);
  }

  /** The account's photo once signed in; the person icon before. */
  function showAccount() {
    var photo = Account.signedIn() && Account.photo();
    Dom.clear(account);
    account.appendChild(photo ? Dom.img(photo, 'topbar-avatar') : Dom.icon('account'));
  }

  /** Gives a section's screen room for the bar; its first row then keeps the page at the top. */
  function attach(s) {
    s.el.classList.add('has-topbar');
    s.content.dataset.top = String(TOP);
  }

  /** Shows the bar over the open section's screen, moved up as far as that screen has scrolled. */
  function update() {
    var s = Router.top();
    var on = !!s && !!SECTIONS[s.nav] && !document.getElementById('app').classList.contains('fullscreen');
    el.hidden = !on;
    if (on) el.style.transform = 'translateY(' + -(s.content._y || 0) + 'px)';
  }

  function contains(node) {
    return !!el && !!node && el.contains(node);
  }

  return { build: build, attach: attach, update: update, contains: contains };
})();

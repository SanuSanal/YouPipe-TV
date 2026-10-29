// The account, opened from the top of the menu like YouTube on TV (js/data/account.js). Signed out it explains the
// sign-in and opens Google's page; signed in it imports the account's subscriptions and history, and signs out.
var AccountScreen = (function () {
  var h = Dom.h;

  function button(label, icon, onSelect, primary) {
    var b = h('div.button.focusable' + (primary ? '.primary' : ''), [Dom.icon(icon), h('span', { text: label })]);
    b._activate = onSelect;
    b.addEventListener('click', onSelect);
    return b;
  }

  function signIn() {
    Overlay.confirm(
      "Open Google's sign-in page?",
      'Open',
      () => Account.signIn(),
      "It opens in place of YouPipe. When YouTube's page shows up, you're signed in: press Back to return, or if " +
        "that doesn't work, hold Back to leave and open YouPipe again.",
    );
  }

  async function importAll(done) {
    Overlay.toast('Importing from your account…');
    try {
      var n = await Account.importAll();
      Overlay.toast('Imported ' + n[0] + ' subscriptions and ' + n[1] + ' videos from your history', 5000);
    } catch (e) {
      Log.add('account import failed: ' + e.message);
      Overlay.toast("Couldn't import from your account");
    }
    if (done) done();
  }

  function create() {
    var s = Screens.base('account', 320);
    s.keep = true;
    var imported = null;

    function render() {
      Dom.clear(s.content);
      if (!Account.signedIn()) {
        Dom.append(s.content, [
          h('h1.page-title.vline', { text: 'Sign in to YouTube' }),
          h('div.account-text', {
            text:
              'Bring your YouTube account to YouPipe: your recommendations on Home, and your YouTube history, Watch ' +
              'later, liked videos and playlists in Library. Your subscriptions and history can also be copied to ' +
              'this TV.',
          }),
          h('div.account-text.secondary', {
            text:
              "Google's sign-in page opens in place of YouPipe. Move between its boxes with the arrows and press OK " +
              'to type. On this TV your account is only read: likes, Watch later and subscriptions you change in ' +
              'YouPipe stay on the TV.',
          }),
          h('div.account-buttons.vline', [button('Sign in', 'account', signIn, true)]),
        ]);
        return;
      }
      var list = h('div.settings-list.vlist', { 'data-group': 'account' });
      [
        [
          'Import subscriptions and watch history',
          imported || 'Copies them from your account to this TV',
          () =>
            importAll(() => {
              imported = 'Done ' + new Date().toLocaleTimeString();
              render();
            }),
        ],
        ['Check the sign-in', 'Asks YouTube whether this TV is still signed in', () => Account.check().then(render, (e) => Overlay.toast("Couldn't reach YouTube: " + e.message))],
        ['Sign out', 'Your library on this TV stays', () => Overlay.confirm('Sign out of Google on this TV?', 'Sign out', () => Account.signOut(), "Google's page opens to sign out; press Back afterwards.")],
      ].forEach((r) => {
        var row = h('div.setting.focusable.vline', { data: { label: r[0] } }, [h('div.setting-text', [h('div.setting-label', { text: r[0] }), h('div.setting-sub', { text: r[1] })])]);
        row._activate = r[2];
        row.addEventListener('click', r[2]);
        list.appendChild(row);
      });
      Dom.append(s.content, [
        h('div.account-head.vline', [Dom.img(Account.photo(), 'account-photo'), h('h1.page-title', { text: 'Signed in to YouTube' })]),
        list,
      ]);
    }

    Account.onChange(() => {
      render();
      if (!s.el.hidden && !Sidenav.contains(Focus.current)) Router.focusScreen();
    });
    s.firstFocus = () => s.content.querySelector('.focusable');
    s.onShow = render;
    return s;
  }

  return { create: create, importAll: importAll };
})();

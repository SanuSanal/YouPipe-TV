// The optional Google account (docs/account.md).
// - Sign-in: like YouPipe on phones, the user signs in on Google's own page. Here it opens inside the app's web engine
//   (config.xml allows navigating to it), which then holds youtube.com's session cookies.
// - Requests: a Tizen web app can't read those cookies (HttpOnly, another origin), so it can't build the SAPISIDHASH
//   header InnerTube wants. Instead the account's lists come from youtube.com's own pages, fetched with the cookies
//   attached; their ytInitialData is the same JSON as an InnerTube browse response.
// - So the account is read-only on Samsung: likes, Watch later and subscriptions made here stay on the TV.
var Account = (function () {
  var LOGIN_URL =
    'https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true' +
    '&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26hl%3Den' +
    '%26next%3Dhttps%253A%252F%252Fwww.youtube.com%252F%253Fapp%253Ddesktop&hl=en';
  var LOGOUT_URL = 'https://accounts.google.com/Logout?continue=https%3A%2F%2Fwww.youtube.com%2F%3Fapp%3Ddesktop';

  // {signedIn, photo, at}: what the last check found, so the menu shows the account before the check returns.
  var state = Store.get('account', null) || { signedIn: false };
  var listeners = [];
  var home = null; // the account's Home from the last check: {at, items}

  function onChange(fn) {
    listeners.push(fn);
  }

  function set(next) {
    var was = state.signedIn;
    state = next;
    Store.set('account', state);
    listeners.forEach((fn) => fn(was !== state.signedIn));
  }

  function signedIn() {
    return !!state.signedIn;
  }

  function photo() {
    return state.photo || null;
  }

  /** youtube.com's desktop page at [path], fetched with the account's cookies: {loggedIn, data}. */
  async function page(path) {
    var s = Settings.get();
    var u = 'https://www.youtube.com' + path + (path.indexOf('?') >= 0 ? '&' : '?') + 'app=desktop&persist_app=1';
    if (s.hl) u += '&hl=' + s.hl;
    if (s.gl) u += '&gl=' + s.gl;
    var html = await Net.getText(u, { credentials: 'include' });
    return { loggedIn: /"LOGGED_IN"\s*:\s*true/.test(html), data: initialData(html) };
  }

  function initialData(html) {
    var m = html.match(/var ytInitialData\s*=\s*(\{[\s\S]*?\});\s*<\/script>/) || html.match(/window\["ytInitialData"\]\s*=\s*(\{[\s\S]*?\});\s*\n/);
    if (!m) throw new Error('no ytInitialData');
    return JSON.parse(m[1]);
  }

  /** The topbar's account photo. */
  function avatarIn(data) {
    var buttons = Parse.nav(data, ['topbar', 'desktopTopbarRenderer', 'topbarButtons']) || [];
    for (var i = 0; i < buttons.length; i++) {
      var b = buttons[i].topbarMenuButtonRenderer;
      if (b && b.avatar) return Parse.bestImage(b.avatar);
    }
    return null;
  }

  function videos(data) {
    return Parse.flatten(Parse.page(data).entries).filter((i) => i.type === 'video' && !i.short);
  }

  /** Asks youtube.com whether the TV is signed in; keeps the account's Home for the Home screen. */
  async function check() {
    var p = await page('/');
    Log.add('account: ' + (p.loggedIn ? 'signed in' : 'signed out'));
    if (p.loggedIn) home = { at: Date.now(), items: videos(p.data) };
    set({ signedIn: p.loggedIn, photo: p.loggedIn ? avatarIn(p.data) : null, at: Date.now() });
    return p.loggedIn;
  }

  /** Opens Google's sign-in page in place of the app; YouPipe checks the result when it's back. */
  function signIn() {
    Store.set('accountPending', { kind: 'in', at: Date.now() });
    location.href = LOGIN_URL;
  }

  /** Signs the TV out of Google (that clears the cookies the app can't touch), then forgets the account. */
  function signOut() {
    set({ signedIn: false });
    Store.set('accountPending', { kind: 'out', at: Date.now() });
    location.href = LOGOUT_URL;
  }

  /** Called at start: 'in' or 'out' when coming back from Google's sign-in or sign-out page, else null. */
  function returning() {
    var p = Store.get('accountPending', null);
    Store.remove('accountPending');
    return p && Date.now() - p.at < 30 * 60 * 1000 ? p.kind : null;
  }

  // The account's lists ---------------------------------------------------------------------------------------------

  async function recommended() {
    if (home && Date.now() - home.at < 60 * 1000) return home.items;
    var p = await page('/');
    return videos(p.data);
  }

  async function history() {
    return videos((await page('/feed/history')).data);
  }

  /** An account playlist's first page: WL (Watch later), LL (liked videos). */
  async function playlist(id) {
    return Parse.playlistPage((await page('/playlist?list=' + id)).data, id).videos;
  }

  async function playlists() {
    return Parse.flatten(Parse.page((await page('/feed/playlists')).data).entries).filter((i) => i.type === 'playlist');
  }

  async function subscriptions() {
    return Parse.flatten(Parse.page((await page('/feed/channels')).data).entries).filter((i) => i.type === 'channel');
  }

  /** Copies the account's subscriptions and YouTube history into the TV's library: [new channels, new videos]. */
  async function importAll() {
    var subs = Library.importSubscriptions(await subscriptions());
    if (subs) SubsFeed.refresh(true).catch((e) => Log.add('subscriptions refresh failed: ' + e.message));
    var videosAdded = Library.importHistory((await history()).filter((v) => !v.live));
    return [subs, videosAdded];
  }

  return {
    onChange: onChange,
    signedIn: signedIn,
    photo: photo,
    check: check,
    signIn: signIn,
    signOut: signOut,
    returning: returning,
    recommended: recommended,
    history: history,
    playlist: playlist,
    playlists: playlists,
    importAll: importAll,
    initialData: initialData,
  };
})();

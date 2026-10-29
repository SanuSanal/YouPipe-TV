// Boot and the remote. Keys go to the open panel first, then the top screen (onKey), then spatial navigation.
// OK activates on release; holding it opens the focused card's options, like YouTube on TV.
var App = (function () {
  var K = Platform.KEY;
  var LONG_PRESS = 600;
  var press = null;
  var keyCount = 0;

  /** In a desktop browser, scales the 1920×1080 stage to the window (on the TV it is 1:1). */
  function fitStage() {
    var stage = document.getElementById('stage');
    var s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
    stage.style.transform = s === 1 ? '' : 'scale(' + s + ')';
  }

  function activate(el) {
    if (!el) return;
    if (el._activate) el._activate();
    else el.click();
  }

  function direction(k) {
    return k === K.LEFT ? 'left' : k === K.RIGHT ? 'right' : k === K.UP ? 'up' : k === K.DOWN ? 'down' : null;
  }

  function onKeyDown(e) {
    keyCount++;
    var k = e.keyCode;
    if (k === K.RED || e.key === '`') {
      Log.toggle();
      return e.preventDefault();
    }
    if (k === K.ENTER) {
      e.preventDefault();
      if (e.repeat || press) return;
      // A screen may take OK itself (the player shows its controls).
      var top = Router.top();
      if (!Overlay.isOpen() && top && top.onKey && top.onKey(e)) return;
      var target = Focus.current;
      if (target && !target.isConnected) {
        // The focused element was replaced (a list re-rendered): focus the screen again instead.
        if (Overlay.isOpen()) Focus.move('down');
        else Router.focusScreen();
        return;
      }
      press = { target: target, done: false };
      press.timer = setTimeout(() => {
        if (press && press.target && press.target._options) {
          press.done = true;
          press.target._options();
        }
      }, LONG_PRESS);
      return;
    }
    var dir = direction(k);
    if (Overlay.isOpen()) {
      if (Platform.isBack(e)) Overlay.close();
      else if (dir) Focus.move(dir);
      else return;
      return e.preventDefault();
    }
    var screen = Router.top();
    if (screen && screen.onKey && screen.onKey(e)) return e.preventDefault();
    if (Platform.isBack(e)) {
      if (Sidenav.contains(Focus.current)) Router.focusScreen();
      else Router.back();
      return e.preventDefault();
    }
    if (dir) {
      if (dir === 'right' && Sidenav.contains(Focus.current)) Router.focusScreen();
      else if (!Focus.move(dir) && dir === 'left' && screen && !screen.fullscreen) Sidenav.enter();
      return e.preventDefault();
    }
  }

  function onKeyUp(e) {
    if (e.keyCode !== K.ENTER || !press) return;
    clearTimeout(press.timer);
    var p = press;
    press = null;
    if (!p.done && p.target && p.target === Focus.current) activate(p.target);
  }

  async function start() {
    fitStage();
    window.addEventListener('resize', fitStage);
    Platform.registerKeys();
    Sidenav.build(document.getElementById('sidenav'));
    Router.init(document.getElementById('screens'));
    Sidenav.register('account', AccountScreen.create);
    Sidenav.register('search', SearchScreen.create);
    Sidenav.register('home', HomeScreen.create);
    Sidenav.register('subscriptions', SubscriptionsScreen.create);
    Sidenav.register('library', LibraryScreen.create);
    Sidenav.register('settings', SettingsScreen.create);
    document.addEventListener('keydown', onKeyDown);
    document.addEventListener('keyup', onKeyUp);
    // Mouse, for the desktop browser: hovering focuses (without scrolling).
    document.addEventListener('mouseover', (e) => {
      var f = e.target.closest && e.target.closest('.focusable');
      if (f && f !== Focus.current && Focus.candidates().indexOf(f) >= 0) Focus.set(f, { noScroll: true });
    });
    Log.add('YouPipe TV ' + Platform.version() + ', ' + (Net.viaProxy ? 'dev proxy' : 'direct') + ', ' + navigator.userAgent);
    await Player.init();
    Sidenav.go('home');
    checkAccount();
    if (/[?&]selftest\b/.test(location.search)) SelfTest.run();
  }

  /**
   * Back from Google's sign-in page, signed in before, or not checked for a week: ask youtube.com whether the TV is
   * signed in. Home starts over when that changed, and a fresh sign-in imports the account's subscriptions and history.
   */
  function checkAccount() {
    var returning = Account.returning();
    if (!returning && !Account.signedIn() && !Account.due()) return;
    var was = Account.signedIn();
    Account.check()
      .then((now) => {
        if (now !== was) Sidenav.go('home', { fresh: true });
        // Newly signed in, or found signed in after the app's storage was cleared: bring the account's things over.
        if (now && (returning === 'in' || !was)) {
          Overlay.toast('Signed in to YouTube');
          AccountScreen.importAll();
        } else if (returning === 'in') {
          Overlay.toast("Not signed in: the sign-in on Google's page didn't finish", 5000);
        } else if (returning === 'out') {
          Overlay.toast(now ? "Still signed in: the sign-out on Google's page didn't finish" : 'Signed out', 5000);
        }
      })
      .catch((e) => Log.add('account check failed: ' + e.message));
  }

  return {
    start: start,
    activate: activate,
    /** Keys pressed so far: screens use it to tell whether the user has moved since they loaded. */
    get keyCount() {
      return keyCount;
    },
  };
})();

window.addEventListener('load', () => {
  App.start().catch((e) => Log.add('start failed: ' + e.message));
});

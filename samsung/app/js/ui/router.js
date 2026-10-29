// Screens and the Back stack.
// A screen is {el, nav, fullscreen, firstFocus(), onShow(), onHide(), onKey(e), onBack(), destroy()}; everything but
// el is optional. Each left-menu section is a root; pushed screens (a channel, a playlist, the player) stack on it.
// Hidden screens stay in the DOM, so coming back keeps their scroll position and focus.
var Router = (function () {
  var stack = [];
  var host = null;

  function top() {
    return stack[stack.length - 1] || null;
  }

  function hide(s) {
    if (!s) return;
    var f = Focus.current;
    if (f && s.el.contains(f)) s.lastFocus = f;
    s.el.hidden = true;
    if (s.onHide) s.onHide();
  }

  /** Removes a screen; a kept root (Sidenav) is only hidden. */
  function destroy(s) {
    hide(s);
    if (s.keep) return;
    if (s.destroy) s.destroy();
    if (s.el.parentNode) s.el.parentNode.removeChild(s.el);
  }

  function show(s) {
    if (s.el.parentNode !== host) host.appendChild(s.el);
    s.el.hidden = false;
    document.getElementById('app').classList.toggle('fullscreen', !!s.fullscreen);
    Sidenav.setActive(s.nav);
    if (s.onShow) s.onShow();
    focusScreen();
  }

  /** Focus back into the top screen: where it was, or its first element. */
  function focusScreen() {
    var s = top();
    if (!s) return;
    var last = s.lastFocus;
    if (last && last.isConnected && last.offsetParent !== null && s.el.contains(last)) Focus.set(last, { instant: true });
    else {
      var first = (s.firstFocus && s.firstFocus()) || Focus.candidates(s.el)[0];
      if (first) Focus.set(first, { instant: true });
      else Focus.blur();
    }
  }

  function push(s) {
    hide(top());
    stack.push(s);
    show(s);
  }

  /** Replaces the whole stack with a root screen (a left-menu section). Kept roots are hidden, not removed. */
  function root(s) {
    while (stack.length) destroy(stack.pop());
    stack.push(s);
    show(s);
  }

  function pop() {
    if (stack.length < 2) return false;
    destroy(stack.pop());
    show(top());
    return true;
  }

  /** Back: the screen first, then the stack, then Home, then the exit dialog. */
  function back() {
    var s = top();
    if (s && s.onBack && s.onBack()) return;
    if (pop()) return;
    if (s && s.nav !== 'home') return Sidenav.go('home');
    Overlay.exitPrompt(() => Platform.exit());
  }

  function init(el) {
    host = el;
  }

  return { init: init, push: push, root: root, pop: pop, back: back, top: top, focusScreen: focusScreen };
})();

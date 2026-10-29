// What differs between the TV and a desktop browser: remote keys, leaving the app, the version.
var Platform = (function () {
  var isTizen = !!(window.tizen && tizen.application);

  /** Key codes, by meaning. A desktop keyboard maps Esc/Backspace to Back. */
  var KEY = {
    LEFT: 37,
    UP: 38,
    RIGHT: 39,
    DOWN: 40,
    ENTER: 13,
    SPACE: 32,
    BACK: 10009,
    ESC: 27,
    BACKSPACE: 8,
    PLAY_PAUSE: 10252,
    PLAY: 415,
    PAUSE: 19,
    STOP: 413,
    FAST_FORWARD: 417,
    REWIND: 412,
    NEXT: 10233,
    PREVIOUS: 10232,
    RED: 403,
    GREEN: 404,
    YELLOW: 405,
    BLUE: 406,
    CHANNEL_UP: 427,
    CHANNEL_DOWN: 428,
    IME_DONE: 65376,
    IME_CANCEL: 65385,
  };

  function registerKeys() {
    if (!window.tizen || !tizen.tvinputdevice) return;
    var keys = [
      'MediaPlayPause',
      'MediaPlay',
      'MediaPause',
      'MediaStop',
      'MediaFastForward',
      'MediaRewind',
      'MediaTrackNext',
      'MediaTrackPrevious',
      'ColorF0Red',
      'ColorF1Green',
      'ColorF2Yellow',
      'ColorF3Blue',
      'ChannelUp',
      'ChannelDown',
    ];
    keys.forEach((k) => {
      try {
        tizen.tvinputdevice.registerKey(k);
      } catch (e) {
        Log.add('registerKey ' + k + ' failed: ' + e.message);
      }
    });
  }

  /** True for Back on the remote, and Esc or Backspace on a keyboard. */
  function isBack(e) {
    return e.keyCode === KEY.BACK || e.keyCode === KEY.ESC || (e.keyCode === KEY.BACKSPACE && !isTyping());
  }

  function isTyping() {
    var a = document.activeElement;
    return !!a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA');
  }

  function exit() {
    if (isTyping()) document.activeElement.blur();
    try {
      tizen.application.getCurrentApplication().exit();
    } catch (e) {
      Log.add('exit: not on a TV');
    }
  }

  /** The app version from config.xml on the TV; the page's meta tag elsewhere. */
  function version() {
    try {
      if (isTizen) return tizen.application.getCurrentApplication().appInfo.version;
    } catch (e) {}
    var meta = document.querySelector('meta[name="yp-version"]');
    return meta ? meta.content : 'dev';
  }

  /** Keeps the screen on while a video plays (screensaver off). */
  function setScreenSaver(on) {
    try {
      webapis.appcommon.setScreenSaver(
        on ? webapis.appcommon.AppCommonScreenSaverState.SCREEN_SAVER_ON : webapis.appcommon.AppCommonScreenSaverState.SCREEN_SAVER_OFF,
      );
    } catch (e) {}
  }

  return {
    KEY: KEY,
    isTizen: isTizen,
    registerKeys: registerKeys,
    isBack: isBack,
    isTyping: isTyping,
    exit: exit,
    version: version,
    setScreenSaver: setScreenSaver,
  };
})();

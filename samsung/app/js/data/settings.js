// User settings, kept on the TV (Store "settings").
var Settings = (function () {
  var DEFAULTS = {
    quality: 'auto', // 'auto' or a maximum height: 1080, 720, 480, 360
    autoplay: true,
    captions: false,
    captionLang: null, // null: the TV's language
    speed: 1,
    sponsorBlock: false,
    sbActions: {}, // category → 'skip' | 'show' | 'off'
    dislikes: true,
    gl: 'US',
    hl: null, // null: the TV's language
  };
  var current = Object.assign({}, DEFAULTS, Store.get('settings', {}));

  function get() {
    return current;
  }

  function set(patch) {
    current = Object.assign({}, current, patch);
    Store.set('settings', current);
  }

  return { get: get, set: set, DEFAULTS: DEFAULTS };
})();

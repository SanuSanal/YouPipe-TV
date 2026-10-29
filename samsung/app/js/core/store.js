// Everything the app keeps lives in localStorage on the TV, as JSON under "yp.<key>" (docs/data.md).
var Store = (function () {
  var PREFIX = 'yp.';

  function get(key, fallback) {
    try {
      var raw = localStorage.getItem(PREFIX + key);
      return raw == null ? fallback : JSON.parse(raw);
    } catch (e) {
      return fallback;
    }
  }

  function set(key, value) {
    try {
      localStorage.setItem(PREFIX + key, JSON.stringify(value));
    } catch (e) {
      Log.add('store ' + key + ' failed: ' + e.message);
    }
  }

  function remove(key) {
    try {
      localStorage.removeItem(PREFIX + key);
    } catch (e) {}
  }

  return { get: get, set: set, remove: remove };
})();

// Network access.
// - On the TV, the app calls YouTube directly: config.xml lists the origins, so the web runtime allows them.
// - In a desktop browser (the dev server on localhost), CORS blocks that, so requests go through the dev
//   server's /proxy (tools/dev-server.mjs). The proxy runs on the same machine, so stream URLs stay on its IP.
var Net = (function () {
  var viaProxy = /^https?:$/.test(location.protocol) && /^(localhost|127\.0\.0\.1)$/.test(location.hostname);

  function url(u) {
    return viaProxy && /^https?:/.test(u) ? '/proxy?u=' + encodeURIComponent(u) : u;
  }

  async function request(u, options, timeoutMs) {
    var ctl = new AbortController();
    var timer = setTimeout(() => ctl.abort(), timeoutMs || 20000);
    try {
      var r = await fetch(url(u), Object.assign({ signal: ctl.signal }, options));
      if (!r.ok) {
        var err = new Error('HTTP ' + r.status + ' from ' + u.split('?')[0]);
        err.status = r.status;
        throw err;
      }
      return r;
    } catch (e) {
      if (e.name === 'AbortError') throw new Error('Timed out: ' + u.split('?')[0]);
      throw e;
    } finally {
      clearTimeout(timer);
    }
  }

  async function postJson(u, body, headers) {
    var r = await request(u, {
      method: 'POST',
      headers: Object.assign({ 'content-type': 'application/json' }, headers || {}),
      body: JSON.stringify(body),
    });
    return r.json();
  }

  async function getJson(u) {
    return (await request(u, {})).json();
  }

  /** [options] go to fetch: the account's pages pass `credentials: 'include'` (js/data/account.js). */
  async function getText(u, options) {
    return (await request(u, options || {})).text();
  }

  return { viaProxy: viaProxy, url: url, postJson: postJson, getJson: getJson, getText: getText };
})();

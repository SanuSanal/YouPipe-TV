// Diagnostics: every line goes to the console (sdb dlog / Web Inspector) and to the on-screen panel.
var Log = (function () {
  var lines = [];
  var panel = null;
  var started = Date.now();

  function add(msg) {
    var line = ((Date.now() - started) / 1000).toFixed(1).padStart(6) + 's  ' + msg;
    console.log('YP| ' + msg);
    lines.push(line);
    if (lines.length > 34) lines.shift();
    panel = panel || document.getElementById('log');
    if (panel) panel.textContent = lines.join('\n');
  }

  function toggle(show) {
    panel = panel || document.getElementById('log');
    panel.hidden = show === undefined ? !panel.hidden : !show;
  }

  return { add: add, toggle: toggle };
})();

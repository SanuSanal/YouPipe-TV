// Layers above the screens: side panels (option lists, info, comments), dialogs and toasts.
// An open layer takes the remote: focus stays inside it and Back closes it (App.onKey).
var Overlay = (function () {
  var h = Dom.h;
  var layers = [];
  var toastTimer = null;

  function host() {
    return document.getElementById('layers');
  }

  function open(layer, returnTo) {
    layer.classList.add('layer', 'open');
    layer._returnTo = returnTo || Focus.current;
    host().appendChild(layer);
    layers.push(layer);
    return layer;
  }

  function close(layer) {
    layer = layer || layers[layers.length - 1];
    if (!layer) return false;
    layers.splice(layers.indexOf(layer), 1);
    layer.classList.remove('open');
    if (layer._onClose) layer._onClose();
    if (layer.parentNode) layer.parentNode.removeChild(layer);
    var back = layer._returnTo;
    if (back && back.isConnected && back.offsetParent !== null) Focus.set(back, { noScroll: true });
    else Router.focusScreen();
    return true;
  }

  function isOpen() {
    return layers.length > 0;
  }

  /** A row of a panel list. */
  function optionRow(item, panel) {
    var row = h('div.panel-row.focusable.vline', [
      item.icon ? Dom.icon(item.icon) : null,
      h('div.panel-row-text', [h('div.panel-row-label', { text: item.label }), item.sub ? h('div.panel-row-sub', { text: item.sub }) : null]),
      item.value != null ? h('div.panel-row-value', { text: item.value }) : null,
      item.checked ? Dom.icon('check', 'panel-check') : null,
      item.color ? h('span.panel-swatch', { style: { background: item.color } }) : null,
    ]);
    row._activate = () => {
      if (!item.keepOpen) close(panel);
      if (item.onSelect) item.onSelect(item);
    };
    row.addEventListener('click', row._activate);
    return row;
  }

  /**
   * A side panel, like YouTube's settings sheet on TV: {title, subtitle, items, content(el), wide, onClose}.
   * Items: {label, sub, value, icon, checked, color, onSelect, keepOpen}. Returns the panel element.
   */
  function panel(opts) {
    var list = h('div.panel-list.vlist.vscroll', { data: { mode: 'keep', pad: '16' } });
    var layer = h('div.panel-layer' + (opts.wide ? '.wide' : ''), [
      h('div.panel-backdrop'),
      h('div.panel', [
        h('div.panel-head', [h('div.panel-title', { text: opts.title || '' }), opts.subtitle ? h('div.panel-subtitle', { text: opts.subtitle }) : null]),
        h('div.panel-viewport', [list]),
      ]),
    ]);
    layer._onClose = opts.onClose;
    layer._list = list;
    (opts.items || []).forEach((it) => list.appendChild(optionRow(it, layer)));
    if (opts.content) opts.content(list, layer);
    open(layer);
    var checked = list.querySelector('.panel-check');
    var first = (checked && checked.closest('.focusable')) || list.querySelector('.focusable');
    if (first) Focus.set(first, { instant: true });
    return layer;
  }

  /** A centred dialog with an action and Cancel. */
  function confirm(message, action, onConfirm, detail) {
    var ok = h('div.button.focusable', { text: action });
    var cancel = h('div.button.focusable', { text: 'Cancel' });
    var layer = h('div.dialog-layer', [
      h('div.panel-backdrop'),
      h('div.dialog', [h('div.dialog-title', { text: message }), detail ? h('div.dialog-detail', { text: detail }) : null, h('div.dialog-buttons', [ok, cancel])]),
    ]);
    ok._activate = () => {
      close(layer);
      onConfirm();
    };
    cancel._activate = () => close(layer);
    ok.addEventListener('click', ok._activate);
    cancel.addEventListener('click', cancel._activate);
    open(layer);
    Focus.set(cancel);
    return layer;
  }

  /** The exit prompt over the whole screen, like YouTube on TV: the mark, the question, Stay and Exit stacked. */
  function exitPrompt(onExit) {
    var stay = h('div.exit-button.focusable', { text: 'Stay' });
    var exit = h('div.exit-button.focusable', { text: 'Exit' });
    var layer = h('div.exit-layer', [
      h('div.exit', [
        Dom.img('logo.svg', 'exit-logo'),
        h('div.exit-title', { text: 'Exit YouPipe?' }),
        h('div.exit-detail', { text: 'Press Back to keep watching' }),
        h('div.exit-buttons.vlist', [stay, exit]),
      ]),
    ]);
    stay._activate = () => close(layer);
    exit._activate = () => {
      close(layer);
      onExit();
    };
    stay.addEventListener('click', stay._activate);
    exit.addEventListener('click', exit._activate);
    open(layer);
    Focus.set(stay);
    return layer;
  }

  function toast(message, ms) {
    var t = document.getElementById('toast');
    t.textContent = message;
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('show'), ms || 3000);
  }

  return { panel: panel, confirm: confirm, exitPrompt: exitPrompt, toast: toast, close: close, isOpen: isOpen, optionRow: optionRow };
})();

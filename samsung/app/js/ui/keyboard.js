// The on-screen keyboard of the Search screen, laid out like YouTube's on TV: letters in a 7-column grid, then
// space, delete, clear and a 123 toggle. A USB or desktop keyboard types into it too (SearchScreen.onKey).
var Keyboard = (function () {
  var h = Dom.h;
  var LETTERS = ['abcdefg', 'hijklmn', 'opqrstu', "vwxyz-'"];
  var SYMBOLS = ['1234567', '890&#()', '@!?:~.,', '/$%+=_"'];

  /** opts: {onChange(text), onSubmit(text)}. Returns {el, value(), set(text), type(char), backspace()}. */
  function create(opts) {
    var text = '';
    var symbols = false;
    var display = h('div.kb-display', [h('span.kb-text'), h('span.kb-caret')]);
    var keys = h('div.kb-keys', { 'data-group': 'keyboard' });
    var el = h('div.keyboard', [display, keys]);

    function changed() {
      display.firstChild.textContent = text;
      display.classList.toggle('empty', !text);
      if (opts.onChange) opts.onChange(text);
    }

    function key(label, action, cls) {
      var k = h('div.kb-key.focusable' + (cls ? '.' + cls : ''), typeof label === 'string' ? { text: label } : null, typeof label === 'string' ? null : label);
      k._activate = action;
      k.addEventListener('click', action);
      return k;
    }

    function render() {
      var focusedIndex = Array.prototype.indexOf.call(keys.querySelectorAll('.kb-key'), Focus.current);
      Dom.clear(keys);
      (symbols ? SYMBOLS : LETTERS).forEach((row) => row.split('').forEach((c) => keys.appendChild(key(c, () => type(c)))));
      // Last two rows: Space (3) ⌫ (2) 123 (2), then Clear (2) Search (5).
      keys.appendChild(key([Dom.icon('space'), h('span', { text: 'Space' })], () => type(' '), 'span3'));
      keys.appendChild(key(Dom.icon('backspace'), backspace, 'span2'));
      keys.appendChild(key(symbols ? 'ABC' : '123', toggle, 'span2'));
      keys.appendChild(key('Clear', () => set(''), 'span2'));
      keys.appendChild(key([Dom.icon('search'), h('span', { text: 'Search' })], () => opts.onSubmit && opts.onSubmit(text), 'span5.primary'));
      if (focusedIndex >= 0) Focus.set(keys.querySelectorAll('.kb-key')[focusedIndex]);
    }

    function type(c) {
      if (text.length < 100) text += c;
      changed();
    }

    function backspace() {
      text = text.slice(0, -1);
      changed();
    }

    function toggle() {
      symbols = !symbols;
      render();
    }

    function set(t) {
      text = t;
      changed();
    }

    render();
    changed();
    return {
      el: el,
      value: () => text,
      set: set,
      type: type,
      backspace: backspace,
      firstKey: () => keys.querySelector('.kb-key'),
    };
  }

  return { create: create };
})();

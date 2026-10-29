// Spatial navigation for the remote (docs/ui.md).
// - Focusable elements have the class "focusable". Only the ring moves: DOM focus stays on the body, so the TV
//   keyboard never opens by itself.
// - Inside a row (.hscroll) or a list (.vlist), Left/Right or Up/Down go to the neighbour in document order.
//   Everywhere else the nearest element in that direction wins.
// - A container with data-group remembers its last focused child: coming back into the group returns there, like
//   YouTube's rows do.
// - The focused element is kept in view: rows (.hscroll) slide sideways, pages (.vscroll) slide up and down.
var Focus = (function () {
  var current = null;
  var listeners = [];

  function visible(el) {
    return el.offsetParent !== null && !el.classList.contains('disabled');
  }

  /** The topmost open layer (a panel or dialog), else the whole app. */
  function scope() {
    var layers = document.querySelectorAll('.layer.open');
    return layers.length ? layers[layers.length - 1] : document.getElementById('app');
  }

  function candidates(root) {
    return Array.prototype.filter.call((root || scope()).querySelectorAll('.focusable'), visible);
  }

  function groupOf(el) {
    return el && el.closest ? el.closest('[data-group]') : null;
  }

  function set(el, opts) {
    if (!el) return;
    var prev = current;
    if (prev && prev !== el) prev.classList.remove('focused');
    current = el;
    el.classList.add('focused');
    var active = document.activeElement;
    if (active && active !== document.body && active !== el && !(opts && opts.keepInput)) active.blur();
    var g = groupOf(el);
    if (g) g._last = el;
    if (!(opts && opts.noScroll)) reveal(el, opts && opts.instant);
    listeners.forEach((fn) => fn(el, prev));
  }

  function offsetWithin(el, ancestor, prop) {
    var v = 0;
    for (var n = el; n && n !== ancestor; n = n.offsetParent) v += n[prop];
    return v;
  }

  function slide(track, axis, value, instant) {
    var key = axis === 'x' ? '_x' : '_y';
    if (track[key] === value) return;
    track[key] = value;
    if (instant) track.style.transition = 'none';
    track.style.transform = axis === 'x' ? 'translateX(' + -value + 'px)' : 'translateY(' + -value + 'px)';
    if (instant) {
      track.offsetHeight; // apply without animating
      track.style.transition = '';
    }
  }

  /** Slides the focused card's row and page so it's in view. */
  function reveal(el, instant) {
    var row = el.closest('.hscroll');
    if (row) {
      var first = row.querySelector('.focusable');
      var max = Math.max(0, row.scrollWidth - row.parentElement.clientWidth);
      var x = el.offsetLeft - (first ? first.offsetLeft : 0);
      slide(row, 'x', Math.max(0, Math.min(x, max)), instant);
    }
    var page = el.closest('.vscroll');
    if (page) {
      var line = el.closest('.vline') || el;
      if (!page.contains(line)) line = el;
      var pad = Number(page.dataset.pad || 0);
      var top = offsetWithin(line, page, 'offsetTop');
      var viewport = page.parentElement.clientHeight;
      var maxY = Math.max(0, page.scrollHeight - viewport);
      var y;
      if (line.classList.contains('vtop')) {
        // A page's header lines (a channel's banner and tabs) keep the page at its top.
        y = 0;
      } else if (page.dataset.mode === 'keep') {
        // Lists: only move when the line would leave the viewport.
        y = page._y || 0;
        var h = line.offsetHeight;
        if (top - pad < y) y = top - pad;
        else if (top + h + pad > y + viewport) y = top + h + pad - viewport;
      } else {
        y = top - pad;
      }
      slide(page, 'y', Math.max(0, Math.min(y, maxY)), instant);
    }
  }

  function siblingIn(container, dir) {
    var list = candidates(container);
    var i = list.indexOf(current);
    if (i < 0) return null;
    return list[i + (dir === 'left' || dir === 'up' ? -1 : 1)] || null;
  }

  function nearest(dir, list) {
    var from = current.getBoundingClientRect();
    var fx = from.left + from.width / 2;
    var fy = from.top + from.height / 2;
    var best = null;
    var bestScore = Infinity;
    list.forEach((el) => {
      if (el === current) return;
      var r = el.getBoundingClientRect();
      // Distance from the nearest edge in the direction of travel, so wide and narrow elements compare fairly.
      var ahead = dir === 'left' ? from.left - r.right : dir === 'right' ? r.left - from.right : dir === 'up' ? from.top - r.bottom : r.top - from.bottom;
      var centerAhead = dir === 'left' ? fx - (r.left + r.width / 2) : dir === 'right' ? r.left + r.width / 2 - fx : dir === 'up' ? fy - (r.top + r.height / 2) : r.top + r.height / 2 - fy;
      if (centerAhead <= 1 || ahead < -from[dir === 'left' || dir === 'right' ? 'width' : 'height'] / 2) return;
      var side;
      if (dir === 'left' || dir === 'right') side = Math.max(0, Math.max(r.top, from.top) - Math.min(r.bottom, from.bottom));
      else side = Math.max(0, Math.max(r.left, from.left) - Math.min(r.right, from.right));
      var score = Math.max(0, ahead) + side * 2;
      if (score < bestScore) {
        bestScore = score;
        best = el;
      }
    });
    return best;
  }

  /** Moves focus; dir is 'left' | 'right' | 'up' | 'down'. Returns false when nothing lies that way. */
  function move(dir) {
    var root = scope();
    if (!current || !current.isConnected || !visible(current) || !root.contains(current)) {
      var first = candidates(root)[0];
      if (first) set(first);
      return !!first;
    }
    var horizontal = dir === 'left' || dir === 'right';
    var container = horizontal ? current.closest('.hscroll') : current.closest('.vlist');
    var target = container && root.contains(container) ? siblingIn(container, dir) : null;
    if (!target) {
      target = nearest(dir, candidates(root));
      // Entering another group returns to where it was left.
      var g = groupOf(target);
      if (target && g && g !== groupOf(current) && g._last && g._last !== target && g._last.isConnected && visible(g._last) && root.contains(g._last)) {
        target = g._last;
      }
    }
    if (target) set(target);
    return !!target;
  }

  /** Clears the ring (the element stays remembered by its group). */
  function blur() {
    if (current) current.classList.remove('focused');
    current = null;
  }

  function onChange(fn) {
    listeners.push(fn);
  }

  return {
    set: set,
    move: move,
    blur: blur,
    reveal: reveal,
    candidates: candidates,
    onChange: onChange,
    get current() {
      return current;
    },
  };
})();

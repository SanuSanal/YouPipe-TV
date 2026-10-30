// The player screen, like YouTube on TV (docs/ui.md):
// - The video fills the screen. OK, Up or Down shows the controls; Left/Right seek straight away with a preview.
// - Controls: title and channel at the top; the seek bar (storyboard preview, chapters, SponsorBlock segments);
//   a row of buttons; and below it Up next (the queue, or related videos) as a grid, 3 across.
// - Back hides the controls, then leaves the player.
var Watch = (function () {
  var h = Dom.h;
  var K = Platform.KEY;
  var HIDE_AFTER = 5000;
  var SAVE_EVERY = 10000;

  var s = null; // the screen while open
  var ui = {};
  var state = null;

  function el(cls, attrs, children) {
    return h(cls, attrs, children);
  }

  // Screen -----------------------------------------------------------------------------------------------------------

  function build() {
    s = { el: el('section.screen.screen-watch'), fullscreen: true, nav: null };
    ui.title = el('div.watch-title');
    ui.channelLine = el('div.watch-channel');
    ui.meta = el('div.watch-meta');
    ui.top = el('div.watch-top', [ui.title, ui.channelLine, ui.meta]);
    ui.captions = el('div.captions');
    ui.spinner = el('div.spinner');
    ui.error = el('div.watch-error');
    ui.played = el('div.bar-played');
    ui.buffered = el('div.bar-buffered');
    ui.segments = el('div.bar-segments');
    ui.chapterTicks = el('div.bar-ticks');
    ui.knob = el('div.bar-knob');
    ui.preview = el('div.seek-preview', [el('div.seek-frame'), el('div.seek-chapter'), el('div.seek-time')]);
    ui.bar = el('div.seekbar.focusable', [el('div.bar-track', [ui.buffered, ui.segments, ui.played, ui.chapterTicks]), ui.knob, ui.preview]);
    ui.bar._activate = () => (state && state.scrubTo != null ? commitScrub() : togglePause());
    ui.time = el('span.watch-time');
    ui.duration = el('span.watch-duration');
    ui.chapterName = el('span.watch-chapter');
    ui.buttons = el('div.watch-buttons', { 'data-group': 'watch-buttons' });
    ui.upNext = el('div.watch-upnext');
    ui.controls = el('div.watch-controls', [
      el('div.watch-bar-row.vline', [ui.bar]),
      el('div.watch-time-row', [ui.time, ui.chapterName, ui.duration]),
      el('div.watch-buttons-row.vline', [ui.buttons]),
      ui.upNext,
    ]);
    ui.countdown = el('div.countdown');
    Dom.append(s.el, [el('div.watch-shade'), ui.captions, ui.top, ui.controls, ui.spinner, ui.error, ui.countdown]);

    s.onKey = onKey;
    s.onBack = onBack;
    s.firstFocus = () => (s.el.classList.contains('controls') ? ui.buttons.querySelector('.play-button') : null);
    s.onHide = () => {
      // Another screen (a channel) opened on top: pause until we're back.
      if (state) {
        state.resumeOnShow = !Player.video.paused;
        Player.video.pause();
        saveProgress();
      }
      document.getElementById('app').classList.remove('watching');
    };
    s.onShow = () => {
      document.getElementById('app').classList.add('watching');
      if (state && state.resumeOnShow) Player.video.play().catch(() => {});
    };
    s.destroy = () => {
      saveProgress();
      teardown();
      Player.stop();
      Platform.setScreenSaver(true);
      document.getElementById('app').classList.remove('watching');
      s = null;
    };
  }

  /**
   * Plays [item] (a video card's item). opts.queue: {items, index, title, more()} for a playlist; then [item] may be
   * null and the queue's current item plays.
   */
  function open(item, opts) {
    opts = opts || {};
    if (!s) {
      build();
      bindVideo();
      Router.push(s);
    } else if (Router.top() !== s) {
      // The player is under another screen: go back to it.
      while (Router.top() !== s && Router.pop()) {}
    }
    var queue = opts.queue || null;
    if (queue && !item) item = queue.items[queue.index];
    play(item, { queue: queue, start: opts.start, startFraction: opts.startFraction, noHistory: opts.noHistory });
  }

  function teardown() {
    if (!state) return;
    clearInterval(state.saveTimer);
    clearTimeout(state.hideTimer);
    clearTimeout(state.scrubTimer);
    clearInterval(state.countdownTimer);
    state.dead = true;
    state = null;
  }

  async function play(item, opts) {
    saveProgress();
    teardown();
    var st = (state = {
      item: item,
      queue: opts.queue,
      info: null,
      meta: null,
      related: [],
      segments: [],
      skipped: {},
      cues: null,
      track: null,
      dislikes: null,
      scrubTo: null,
      scrubCount: 0,
      noHistory: !!opts.noHistory,
    });
    Platform.setScreenSaver(false);
    ui.error.textContent = '';
    s.el.classList.remove('failed');
    s.el.classList.add('loading');
    ui.title.textContent = item.title || '';
    ui.channelLine.textContent = item.channel || '';
    ui.meta.textContent = '';
    ui.captions.textContent = '';
    Dom.clear(ui.segments);
    Dom.clear(ui.chapterTicks);
    renderButtons();
    renderUpNext();
    showControls(false);
    var metaPromise = InnerTube.next(item.id, null)
      .then((m) => {
        if (st.dead) return;
        st.meta = m;
        st.related = m.related.filter((r) => r.type === 'video' && !r.short && r.id !== item.id);
        renderMeta();
        renderButtons();
        renderUpNext();
        renderChapters();
      })
      .catch((e) => Log.add('next ' + item.id + ' failed: ' + e.message));
    try {
      var info = await InnerTube.player(item.id);
      if (st.dead) return;
      if (info.status !== 'OK') throw new Error(info.reason || info.status);
      st.info = info;
      if (!st.item.title) st.item = Object.assign({}, st.item, { title: info.title, channel: info.channel, channelId: info.channelId, thumb: info.thumb });
      ui.title.textContent = info.title;
      if (!ui.channelLine.textContent) ui.channelLine.textContent = info.channel;
      var start =
        opts.start != null ? opts.start : opts.startFraction != null ? Math.floor(info.lengthSeconds * opts.startFraction) : resumePoint(item.id, info);
      await Player.load(info, start);
      if (st.dead) return;
      // play() only settles once frames flow, so don't wait on it (a stalled stream would hang the caller).
      Player.video.play().catch((e) => Log.add('play(): ' + e.message));
      if (start && opts.start == null && opts.startFraction == null) Overlay.toast('Resuming from ' + Format.time(start));
      st.saveTimer = setInterval(saveProgress, SAVE_EVERY);
      SponsorBlock.segments(item.id).then((segs) => {
        if (st.dead) return;
        st.segments = segs;
        renderSegments();
      });
      Dislikes.count(item.id).then((n) => {
        if (st.dead || n == null) return;
        st.dislikes = n;
        renderButtons();
      });
      if (Settings.get().captions) {
        var lang = Settings.get().captionLang || (navigator.language || 'en').split('-')[0];
        var track = Captions.pick(info.captions, lang);
        if (track) setCaptions(track);
      }
      await metaPromise;
    } catch (e) {
      if (st.dead) return;
      Log.add('play ' + item.id + ' failed: ' + e.message);
      s.el.classList.remove('loading');
      s.el.classList.add('failed');
      ui.error.textContent = "Couldn't play this video. " + e.message;
      showControls(true);
    }
  }

  function resumePoint(id, info) {
    if (info.isLive) return 0;
    var p = Library.progress(id);
    if (!p || !p.duration) return 0;
    return p.position > 10 && p.position < p.duration - 30 ? p.position : 0;
  }

  function saveProgress() {
    if (!state || !state.info || state.info.isLive || state.noHistory) return;
    var v = Player.video;
    if (!v || !isFinite(v.duration) || v.currentTime < 3) return;
    Library.saveProgress(state.item, v.currentTime, v.duration);
  }

  // Video events ------------------------------------------------------------------------------------------------------

  function bindVideo() {
    var v = Player.video;
    if (v._bound) return;
    v._bound = true;
    v.addEventListener('timeupdate', onTime);
    v.addEventListener('progress', renderBar);
    v.addEventListener('waiting', () => s && s.el.classList.add('loading'));
    v.addEventListener('playing', () => {
      if (!s) return;
      s.el.classList.remove('loading');
      renderButtons();
      scheduleHide();
    });
    v.addEventListener('pause', () => {
      if (!s) return;
      renderButtons();
      showControls(true);
    });
    v.addEventListener('ended', onEnded);
  }

  function onTime() {
    if (!s || !state) return;
    var v = Player.video;
    var t = v.currentTime;
    // SponsorBlock: skip each "skip" segment once.
    for (var i = 0; i < state.segments.length; i++) {
      var seg = state.segments[i];
      if (seg.action === 'skip' && !state.skipped[i] && t >= seg.start && t < seg.end - 0.5) {
        state.skipped[i] = true;
        v.currentTime = seg.end;
        Overlay.toast('Skipped ' + seg.label.toLowerCase());
        break;
      }
    }
    if (state.cues) ui.captions.textContent = Captions.at(state.cues, t);
    if (s.el.classList.contains('controls')) renderBar();
  }

  function onEnded() {
    if (!state) return;
    saveProgress();
    var next = nextItem();
    if (!next) return showControls(true);
    if (state.queue) return goNext();
    if (!Settings.get().autoplay) return showControls(true);
    // YouTube's countdown before the next video.
    var left = 5;
    var c = ui.countdown;
    Dom.clear(c);
    var cancel = el('div.button.focusable', { text: 'Cancel' });
    var now = el('div.button.focusable.primary', { text: 'Play now' });
    var count = el('div.countdown-label', { text: 'Up next in ' + left });
    Dom.append(c, [count, el('div.countdown-card', [Dom.img(next.thumb, 'countdown-thumb'), el('div.countdown-title', { text: next.title }), el('div.countdown-channel', { text: next.channel || '' })]), el('div.countdown-buttons', [now, cancel])]);
    c.classList.add('show');
    s.el.classList.add('counting');
    Focus.set(now);
    function stopCountdown() {
      clearInterval(state.countdownTimer);
      c.classList.remove('show');
      s.el.classList.remove('counting');
    }
    now._activate = () => {
      stopCountdown();
      goNext();
    };
    cancel._activate = () => {
      stopCountdown();
      showControls(true);
    };
    state.countdownTimer = setInterval(() => {
      left--;
      count.textContent = 'Up next in ' + left;
      if (left <= 0) now._activate();
    }, 1000);
  }

  // Queue -------------------------------------------------------------------------------------------------------------

  function nextItem() {
    if (!state) return null;
    var q = state.queue;
    if (q && q.index < q.items.length - 1) return q.items[q.index + 1];
    if (q) return null;
    var watched = {};
    Library.history()
      .slice(0, 50)
      .forEach((e) => (watched[e.video.id] = 1));
    return state.related.filter((r) => !watched[r.id])[0] || state.related[0] || null;
  }

  async function goNext() {
    if (!state) return;
    var q = state.queue;
    if (q && q.index >= q.items.length - 1 && q.more) {
      var more = await q.more().catch(() => []);
      if (more.length) q.items = q.items.concat(more.filter((m) => q.items.indexOf(m) < 0));
    }
    if (q && q.index < q.items.length - 1) {
      q.index++;
      return play(q.items[q.index], { queue: q });
    }
    var next = nextItem();
    if (next) play(next, { queue: null });
  }

  function goPrevious() {
    var v = Player.video;
    var q = state && state.queue;
    if (v.currentTime > 5 || !q || q.index === 0) {
      v.currentTime = 0;
      return;
    }
    q.index--;
    play(q.items[q.index], { queue: q });
  }

  // Controls -----------------------------------------------------------------------------------------------------------

  function showControls(focusPlay) {
    if (!s) return;
    var wasHidden = !s.el.classList.contains('controls');
    s.el.classList.add('controls');
    renderBar();
    if (focusPlay || wasHidden || !s.el.contains(Focus.current)) {
      var target = focusPlay === 'bar' ? ui.bar : ui.buttons.querySelector('.play-button') || ui.bar;
      Focus.set(target, { instant: true });
    }
    scheduleHide();
  }

  function hideControls() {
    if (!s || !state || state.scrubTo != null) return;
    if (s.el.classList.contains('failed') || s.el.classList.contains('counting')) return;
    s.el.classList.remove('controls');
    Focus.blur();
  }

  function scheduleHide() {
    if (!state) return;
    clearTimeout(state.hideTimer);
    state.hideTimer = setTimeout(() => {
      if (!Player.video.paused && !Overlay.isOpen()) hideControls();
    }, HIDE_AFTER);
  }

  function togglePause() {
    var v = Player.video;
    if (v.paused) v.play().catch(() => {});
    else v.pause();
  }

  function button(iconName, label, action, cls) {
    var b = el('div.watch-button.focusable' + (cls ? '.' + cls : ''), [Dom.icon(iconName), label ? el('span', { text: label }) : null]);
    b._activate = action;
    b.addEventListener('click', action);
    return b;
  }

  function renderButtons() {
    if (!s || !state) return;
    var focusedKey = ui.buttons.contains(Focus.current) ? Focus.current.dataset.key : null;
    Dom.clear(ui.buttons);
    var v = Player.video;
    var item = state.item;
    var meta = state.meta;
    var channel = meta && meta.channel && meta.channel.id ? meta.channel : item.channelId ? { id: item.channelId, name: item.channel } : null;
    var liked = Library.has('liked', item.id);
    var left = [
      ['previous', button('previous', null, goPrevious)],
      ['play', button(v.paused ? 'play' : 'pause', null, togglePause, 'play-button')],
      ['next', button('next', null, goNext)],
    ];
    var right = [
      [
        'like',
        button('like', (meta && meta.likes) || 'Like', () => {
          Overlay.toast(Library.toggle('liked', item) ? 'Added to Liked videos' : 'Removed from Liked videos');
          renderButtons();
        }, liked ? 'on' : ''),
      ],
      state.dislikes != null ? ['dislike', button('dislike', Format.count(state.dislikes), () => Overlay.toast('Estimated by Return YouTube Dislike'))] : null,
      [
        'save',
        button('watchLater', Library.has('watchLater', item.id) ? 'Saved' : 'Save', () => {
          Overlay.toast(Library.toggle('watchLater', item) ? 'Saved to Watch later' : 'Removed from Watch later');
          renderButtons();
        }),
      ],
      channel
        ? [
            'subscribe',
            button('bell', Library.isSubscribed(channel.id) ? 'Subscribed' : 'Subscribe', () => {
              var on = Library.toggleSubscription(channel);
              Overlay.toast(on ? 'Subscribed to ' + channel.name : 'Unsubscribed from ' + channel.name);
              renderButtons();
            }, Library.isSubscribed(channel.id) ? 'on' : ''),
          ]
        : null,
      ['captions', button('captions', null, captionsPanel, state.track ? 'on' : '')],
      ['settings', button('tune', null, settingsPanel)],
      ['info', button('info', null, infoPanel)],
      ['comments', button('comments', null, commentsPanel)],
      channel ? ['channel', button('account', null, () => ChannelScreen.open(channel))] : null,
    ].filter(Boolean);
    var leftBox = el('div.watch-buttons-left');
    var rightBox = el('div.watch-buttons-right');
    left.forEach((p) => {
      p[1].dataset.key = p[0];
      leftBox.appendChild(p[1]);
    });
    right.forEach((p) => {
      p[1].dataset.key = p[0];
      rightBox.appendChild(p[1]);
    });
    Dom.append(ui.buttons, [leftBox, rightBox]);
    if (focusedKey) {
      var again = ui.buttons.querySelector('[data-key="' + focusedKey + '"]');
      if (again) Focus.set(again, { noScroll: true });
    }
  }

  function renderMeta() {
    var m = state.meta;
    if (!m) return;
    if (m.title) ui.title.textContent = m.title;
    Dom.clear(ui.channelLine);
    Dom.append(ui.channelLine, [m.channel.avatar ? Dom.img(m.channel.avatar, 'watch-avatar') : null, el('span', { text: m.channel.name }), m.channel.subs ? el('span.watch-subs', { text: m.channel.subs }) : null]);
    ui.meta.textContent = [m.viewsShort || m.views, m.relativeDate || m.date].filter(Boolean).join(' • ');
  }

  function renderUpNext() {
    if (!s || !state) return;
    Dom.clear(ui.upNext);
    var q = state.queue;
    var items = q ? q.items.slice(q.index + 1) : state.related;
    if (!items.length) return;
    var grid = Cards.grid({
      cardOpts: {
        play: (it) => {
          if (q) {
            q.index = q.items.indexOf(it);
            play(it, { queue: q });
          } else play(it, { queue: null });
        },
      },
    });
    grid.add(items.slice(0, 30));
    Dom.append(ui.upNext, [el('div.row-title', { text: q ? 'Up next in ' + (q.title || 'this playlist') : 'Up next' }), grid.el]);
  }

  function chapterAt(t) {
    var ch = state && state.meta ? state.meta.chapters : [];
    var cur = null;
    for (var i = 0; i < ch.length; i++) if (ch[i].start <= t) cur = ch[i];
    return cur;
  }

  function renderChapters() {
    Dom.clear(ui.chapterTicks);
    var d = durationOf();
    if (!d || !state.meta) return;
    state.meta.chapters.forEach((c) => {
      if (c.start > 0) ui.chapterTicks.appendChild(el('div.bar-tick', { style: { left: (100 * c.start) / d + '%' } }));
    });
  }

  function renderSegments() {
    Dom.clear(ui.segments);
    var d = durationOf();
    if (!d) return;
    state.segments.forEach((seg) => {
      ui.segments.appendChild(
        el('div.bar-segment', { style: { left: (100 * seg.start) / d + '%', width: (100 * (seg.end - seg.start)) / d + '%', background: seg.color } }),
      );
    });
  }

  function durationOf() {
    var v = Player.video;
    if (v && isFinite(v.duration) && v.duration > 0) return v.duration;
    return state && state.info ? state.info.lengthSeconds : 0;
  }

  function renderBar() {
    if (!s || !state) return;
    var v = Player.video;
    var live = state.info && state.info.isLive;
    var d = durationOf();
    var t = state.scrubTo != null ? state.scrubTo : v.currentTime;
    s.el.classList.toggle('live', !!live);
    if (live) {
      ui.played.style.width = '100%';
      ui.knob.style.left = '100%';
      ui.time.textContent = 'LIVE';
      ui.duration.textContent = '';
      return;
    }
    if (d) {
      ui.played.style.width = (100 * v.currentTime) / d + '%';
      var b = v.buffered.length ? v.buffered.end(v.buffered.length - 1) : 0;
      ui.buffered.style.width = (100 * b) / d + '%';
      ui.knob.style.left = (100 * t) / d + '%';
    }
    ui.time.textContent = Format.time(t);
    ui.duration.textContent = Format.time(d);
    var ch = chapterAt(t);
    ui.chapterName.textContent = ch ? ch.title : '';
    if (!ui.segments.firstChild && state.segments.length) renderSegments();
    if (!ui.chapterTicks.firstChild && state.meta && state.meta.chapters.length) renderChapters();
  }

  // Seeking -------------------------------------------------------------------------------------------------------------

  /** Moves the pending seek position; it's applied when the keys stop (or on OK). */
  function scrub(dir) {
    if (!state || !state.info || state.info.isLive) return liveSeek(dir);
    var v = Player.video;
    var d = durationOf();
    var now = Date.now();
    state.scrubCount = now - (state.lastScrub || 0) < 500 ? state.scrubCount + 1 : 0;
    state.lastScrub = now;
    var step = state.scrubCount > 20 ? 60 : state.scrubCount > 8 ? 30 : 10;
    var from = state.scrubTo != null ? state.scrubTo : v.currentTime;
    state.scrubTo = Math.max(0, Math.min(d - 1, from + dir * step));
    s.el.classList.add('scrubbing');
    showPreview(state.scrubTo);
    renderBar();
    clearTimeout(state.scrubTimer);
    state.scrubTimer = setTimeout(commitScrub, 800);
    scheduleHide();
  }

  function liveSeek(dir) {
    var v = Player.video;
    var range = v.seekable.length ? [v.seekable.start(0), v.seekable.end(v.seekable.length - 1)] : null;
    if (!range) return;
    v.currentTime = Math.max(range[0], Math.min(range[1], v.currentTime + dir * 10));
  }

  function commitScrub() {
    if (!state || state.scrubTo == null) return;
    clearTimeout(state.scrubTimer);
    Player.video.currentTime = state.scrubTo;
    state.scrubTo = null;
    s.el.classList.remove('scrubbing');
    renderBar();
    scheduleHide();
  }

  function showPreview(t) {
    var d = durationOf();
    var frameEl = ui.preview.querySelector('.seek-frame');
    var sb = state.info && state.info.storyboard;
    if (sb) {
      var f = Storyboard.frame(sb, t);
      var scale = 320 / f.width;
      frameEl.style.backgroundImage = 'url("' + Net.url(f.url) + '")';
      frameEl.style.backgroundSize = f.sheetWidth * scale + 'px ' + f.sheetHeight * scale + 'px';
      frameEl.style.backgroundPosition = -f.x * scale + 'px ' + -f.y * scale + 'px';
      frameEl.style.height = f.height * scale + 'px';
      frameEl.hidden = false;
    } else frameEl.hidden = true;
    var ch = chapterAt(t);
    ui.preview.querySelector('.seek-chapter').textContent = ch ? ch.title : '';
    ui.preview.querySelector('.seek-time').textContent = Format.time(t);
    ui.preview.style.left = d ? Math.max(10, Math.min(90, (100 * t) / d)) + '%' : '50%';
  }

  // Panels ---------------------------------------------------------------------------------------------------------------

  async function setCaptions(track) {
    if (!state) return;
    state.track = track;
    state.cues = null;
    ui.captions.textContent = '';
    renderButtons();
    if (!track) return;
    try {
      var cues = await Captions.load(track);
      if (state && state.track === track) state.cues = cues;
    } catch (e) {
      Overlay.toast("Couldn't load captions");
      Log.add('captions failed: ' + e.message);
    }
  }

  function captionsPanel() {
    var tracks = (state.info && state.info.captions) || [];
    if (!tracks.length) return Overlay.toast('No captions for this video');
    Overlay.panel({
      title: 'Captions',
      items: [{ label: 'Off', checked: !state.track, onSelect: () => setCaptions(null) }].concat(
        tracks.map((t) => ({ label: t.name, checked: state.track === t, onSelect: () => setCaptions(t) })),
      ),
    });
  }

  function settingsPanel() {
    var heights = Player.heights();
    var sel = Player.selectedHeight();
    var v = Player.video;
    Overlay.panel({
      title: 'Settings',
      items: [
        {
          label: 'Quality',
          value: sel === 'auto' ? 'Auto (' + Player.quality() + ')' : sel + 'p',
          icon: 'tune',
          onSelect: () =>
            Overlay.panel({
              title: 'Quality',
              items: [{ label: 'Auto', checked: sel === 'auto', onSelect: () => Player.setHeight('auto') }].concat(
                heights.map((hgt) => ({ label: hgt + 'p', checked: sel === hgt, onSelect: () => Player.setHeight(hgt) })),
              ),
            }),
        },
        {
          label: 'Playback speed',
          value: v.playbackRate === 1 ? 'Normal' : v.playbackRate + '×',
          icon: 'speed',
          onSelect: () =>
            Overlay.panel({
              title: 'Playback speed',
              items: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].map((r) => ({ label: r === 1 ? 'Normal' : r + '×', checked: v.playbackRate === r, onSelect: () => (v.playbackRate = r) })),
            }),
        },
        { label: 'Captions', value: state.track ? state.track.name : 'Off', icon: 'captions', onSelect: captionsPanel },
        {
          label: 'Autoplay',
          value: Settings.get().autoplay ? 'On' : 'Off',
          icon: 'playlistPlay',
          onSelect: () => Settings.set({ autoplay: !Settings.get().autoplay }),
        },
      ],
    });
  }

  function infoPanel() {
    var m = state.meta;
    var info = state.info;
    Overlay.panel({
      title: (m && m.title) || state.item.title,
      subtitle: m ? [m.views, m.date].filter(Boolean).join(' • ') : '',
      wide: true,
      content: (list) => {
        var chapters = m ? m.chapters : [];
        if (chapters.length) {
          list.appendChild(el('div.panel-heading.vline', { text: 'Chapters' }));
          chapters.forEach((c) => {
            var row = el('div.panel-row.chapter-row.focusable.vline', [
              c.thumb ? Dom.img(c.thumb, 'chapter-thumb') : null,
              el('div.panel-row-text', [el('div.panel-row-label', { text: c.title }), el('div.panel-row-sub', { text: Format.time(c.start) })]),
            ]);
            row._activate = () => {
              Overlay.close();
              Player.video.currentTime = c.start;
            };
            list.appendChild(row);
          });
          list.appendChild(el('div.panel-heading.vline', { text: 'Description' }));
        }
        var text = (m && m.description) || (info && info.description) || 'No description';
        // Each paragraph is a stop for the remote, so long descriptions scroll.
        text
          .split(/\n{2,}/)
          .map((p) => p.trim())
          .filter(Boolean)
          .forEach((p) => list.appendChild(el('div.panel-paragraph.focusable.vline', { text: p })));
      },
    });
  }

  function commentsPanel() {
    var token = state.meta && state.meta.commentsToken;
    if (!token) return Overlay.toast(state.meta ? 'Comments are turned off' : 'Still loading…');
    var loading = false;
    var layer = Overlay.panel({
      title: 'Comments',
      wide: true,
      content: (list) => list.appendChild(el('div.panel-paragraph.vline', { text: 'Loading…' })),
    });
    var list = layer._list;
    async function load() {
      if (!token || loading) return;
      loading = true;
      try {
        var page = await InnerTube.comments(token);
        token = page.continuation;
        var placeholder = list.querySelector('.panel-paragraph:not(.focusable)');
        if (placeholder) placeholder.remove();
        if (page.count) layer.querySelector('.panel-title').textContent = 'Comments • ' + page.count;
        page.comments.forEach((c) => {
          list.appendChild(
            el('div.comment.focusable.vline', [
              Dom.img(c.avatar, 'comment-avatar'),
              el('div.comment-body', [
                el('div.comment-head', { text: [c.author, c.published].filter(Boolean).join(' • ') + (c.pinned ? '  📌' : '') }),
                el('div.comment-text', { text: c.text }),
                el('div.comment-foot', { text: [c.likes ? '👍 ' + c.likes : '', c.replyCount ? c.replyCount + ' replies' : ''].filter(Boolean).join('   ') }),
              ]),
            ]),
          );
        });
        if (!list.querySelector('.focusable')) list.appendChild(el('div.panel-paragraph.vline', { text: 'No comments yet' }));
        else if (!layer.contains(Focus.current)) Focus.set(list.querySelector('.focusable'));
      } catch (e) {
        Overlay.toast("Couldn't load comments");
        Log.add('comments failed: ' + e.message);
      } finally {
        loading = false;
      }
    }
    list._nearEnd = load;
    load();
  }

  // Keys ----------------------------------------------------------------------------------------------------------------

  function onKey(e) {
    var k = e.keyCode;
    // The autoplay countdown's buttons take the keys.
    if (s.el.classList.contains('counting')) return false;
    var controls = s.el.classList.contains('controls');
    if (k === K.PLAY_PAUSE || k === K.SPACE) {
      togglePause();
      return true;
    }
    if (k === K.PLAY) return Player.video.play().catch(() => {}), true;
    if (k === K.PAUSE) return Player.video.pause(), true;
    if (k === K.STOP) return Router.pop(), true;
    if (k === K.NEXT || k === K.CHANNEL_UP) return goNext(), true;
    if (k === K.PREVIOUS || k === K.CHANNEL_DOWN) return goPrevious(), true;
    if (k === K.FAST_FORWARD || k === K.REWIND) {
      if (!controls) showControls('bar');
      scrub(k === K.FAST_FORWARD ? 1 : -1);
      return true;
    }
    if (!controls) {
      if (k === K.LEFT || k === K.RIGHT) {
        showControls('bar');
        scrub(k === K.RIGHT ? 1 : -1);
        return true;
      }
      if (k === K.ENTER || k === K.UP || k === K.DOWN) {
        showControls(true);
        return true;
      }
      return false;
    }
    scheduleHide();
    if (Focus.current === ui.bar && (k === K.LEFT || k === K.RIGHT)) {
      scrub(k === K.RIGHT ? 1 : -1);
      return true;
    }
    if (k === K.UP && Focus.current === ui.bar) {
      hideControls();
      return true;
    }
    // Left and Right stay in Up next's row: at its sides the nearest element that way is a button above, and the
    // controls would slide back down.
    if ((k === K.LEFT || k === K.RIGHT) && ui.upNext.contains(Focus.current)) {
      var cards = Focus.candidates(ui.upNext);
      var next = cards[cards.indexOf(Focus.current) + (k === K.RIGHT ? 1 : -1)];
      if (next && next.offsetTop === Focus.current.offsetTop) Focus.set(next);
      return true;
    }
    return false;
  }

  function onBack() {
    if (state && state.scrubTo != null) {
      state.scrubTo = null;
      s.el.classList.remove('scrubbing');
      renderBar();
      return true;
    }
    if (s.el.classList.contains('counting')) {
      clearInterval(state.countdownTimer);
      ui.countdown.classList.remove('show');
      s.el.classList.remove('counting');
      showControls(true);
      return true;
    }
    if (s.el.classList.contains('controls') && !s.el.classList.contains('failed') && !Player.video.paused) {
      hideControls();
      return true;
    }
    return false; // the Router pops the player
  }

  // Focus in Up next slides the controls up until the focused card's row sits above the screen's bottom edge; the title
  // at the top fades out meanwhile, as the controls slide up past it.
  var BOTTOM = 1080 - 72;
  Focus.onChange((now) => {
    if (!s) return;
    var inside = !!now && ui.upNext.contains(now);
    var top = ui.controls.offsetTop;
    for (var n = now; inside && n && n !== ui.controls; n = n.offsetParent) top += n.offsetTop;
    var y = inside ? Math.max(0, top + now.offsetHeight - BOTTOM) : 0;
    s.el.classList.toggle('upnext', inside);
    ui.controls.style.transform = y ? 'translateY(' + -y + 'px)' : '';
  });

  return {
    open: open,
    get state() {
      return state;
    },
  };
})();

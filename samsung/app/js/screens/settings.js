// Settings: a list on the left; each row opens its choices in a side panel, like YouTube on TV.
var SettingsScreen = (function () {
  var h = Dom.h;
  var QUALITIES = [
    ['auto', 'Auto (up to 1080p)'],
    [1080, '1080p'],
    [720, '720p'],
    [480, '480p'],
    [360, '360p'],
  ];
  var SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
  var REGIONS = [
    ['US', 'United States'],
    ['GB', 'United Kingdom'],
    ['IE', 'Ireland'],
    ['IN', 'India'],
    ['CA', 'Canada'],
    ['AU', 'Australia'],
    ['DE', 'Germany'],
    ['FR', 'France'],
    ['ES', 'Spain'],
    ['IT', 'Italy'],
    ['NL', 'Netherlands'],
    ['BR', 'Brazil'],
    ['MX', 'Mexico'],
    ['JP', 'Japan'],
    ['KR', 'South Korea'],
    ['AE', 'United Arab Emirates'],
  ];
  var LANGUAGES = [
    [null, 'Same as the TV'],
    ['en', 'English'],
    ['de', 'Deutsch'],
    ['es', 'Español'],
    ['fr', 'Français'],
    ['hi', 'हिन्दी'],
    ['it', 'Italiano'],
    ['ja', '日本語'],
    ['ko', '한국어'],
    ['ml', 'മലയാളം'],
    ['nl', 'Nederlands'],
    ['pt', 'Português'],
    ['ta', 'தமிழ்'],
  ];

  function labelOf(pairs, value) {
    var p = pairs.filter((x) => x[0] === value)[0];
    return p ? p[1] : String(value);
  }

  function onOff(v) {
    return v ? 'On' : 'Off';
  }

  function choose(title, pairs, value, apply) {
    Overlay.panel({
      title: title,
      items: pairs.map((p) => ({
        label: p[1],
        checked: p[0] === value,
        onSelect: () => {
          apply(p[0]);
          var top = Router.top();
          if (top && top.refresh && top.el.classList.contains('screen-settings')) top.refresh();
        },
      })),
    });
  }

  /** Region and language change what YouTube returns: Home and Search start over on the next visit. */
  function localeChanged() {
    Sidenav.reset('home');
    Sidenav.reset('search');
  }

  function sponsorBlockCategories(refresh) {
    var actions = Settings.get().sbActions || {};
    Overlay.panel({
      title: 'SponsorBlock categories',
      subtitle: 'What to do with each kind of segment',
      items: SponsorBlock.CATEGORIES.map((c) => {
        var action = actions[c.key] || c.action;
        return {
          label: c.label,
          color: c.color,
          value: { skip: 'Skip', show: 'Show on the bar', off: 'Off' }[action],
          onSelect: () =>
            choose(
              c.label,
              [
                ['skip', 'Skip'],
                ['show', 'Show on the bar'],
                ['off', 'Off'],
              ],
              action,
              (a) => {
                var next = Object.assign({}, Settings.get().sbActions);
                next[c.key] = a;
                Settings.set({ sbActions: next });
                refresh();
              },
            ),
        };
      }),
    });
  }

  async function checkUpdates() {
    Overlay.toast('Checking for updates…');
    try {
      var latest = await Updates.check(true);
      // The Version row shows what the check found, before the prompt opens over it.
      var top = Router.top();
      if (top && top.refresh && top.el.classList.contains('screen-settings') && !Overlay.isOpen()) top.refresh();
      if (Updates.isNewer(latest, Platform.version())) Updates.offer(latest);
      else Overlay.toast('YouPipe is up to date (' + Platform.version() + ')');
    } catch (e) {
      Overlay.toast("Couldn't check for updates: " + e.message);
    }
  }

  function create() {
    var s = Screens.base('settings', 320);
    var list = h('div.settings-list.vlist', { 'data-group': 'settings' });
    Dom.append(s.content, [h('h1.page-title.vline', { text: 'Settings' }), list]);

    function rows() {
      var st = Settings.get();
      return [
        ['Playback'],
        ['Video quality', labelOf(QUALITIES, st.quality), () => choose('Video quality', QUALITIES, st.quality, (v) => Settings.set({ quality: v }))],
        ['Autoplay next video', onOff(st.autoplay), () => Settings.set({ autoplay: !st.autoplay })],
        ['Captions', onOff(st.captions), () => Settings.set({ captions: !st.captions })],
        ['Caption language', labelOf(LANGUAGES, st.captionLang), () => choose('Caption language', LANGUAGES, st.captionLang, (v) => Settings.set({ captionLang: v }))],
        [
          'Playback speed',
          st.speed === 1 ? 'Normal' : st.speed + '×',
          () => choose('Playback speed', SPEEDS.map((v) => [v, v === 1 ? 'Normal' : v + '×']), st.speed, (v) => Settings.set({ speed: v })),
        ],
        ['Extras'],
        ['SponsorBlock: skip sponsors and more', onOff(st.sponsorBlock), () => Settings.set({ sponsorBlock: !st.sponsorBlock }), 'Community segments from sponsor.ajay.app'],
        st.sponsorBlock ? ['Categories', '', () => sponsorBlockCategories(render)] : null,
        ['Return YouTube Dislike', onOff(st.dislikes), () => Settings.set({ dislikes: !st.dislikes }), 'Estimated dislike counts from returnyoutubedislike.com'],
        ['Content'],
        [
          'Region',
          labelOf(REGIONS, st.gl),
          () =>
            choose('Region', REGIONS, st.gl, (v) => {
              Settings.set({ gl: v });
              localeChanged();
            }),
          'The country YouTube picks videos for',
        ],
        [
          'Language',
          labelOf(LANGUAGES, st.hl),
          () =>
            choose('Language', LANGUAGES, st.hl, (v) => {
              Settings.set({ hl: v });
              localeChanged();
            }),
          'The language of titles and dates from YouTube',
        ],
        ['Privacy'],
        [
          'Clear watch history',
          Library.history().length + ' videos',
          () =>
            Overlay.confirm('Clear watch history?', 'Clear', () => {
              Library.clear('history');
              render();
            }),
        ],
        [
          'Clear search history',
          Library.searches().length + ' searches',
          () =>
            Overlay.confirm('Clear search history?', 'Clear', () => {
              Library.clear('searches');
              render();
            }),
        ],
        ['About'],
        ['Version', Platform.version(), checkUpdates, Updates.available() ? 'Version ' + Updates.available() + ' is available' : 'Check for updates'],
        ['Source code', 'github.com/' + Updates.REPO, null],
        ['Run the self test', '', () => SelfTest.run(), 'Plays a few videos and reports what works (diagnostics)'],
        ['Show the log', '', () => Log.toggle(), 'Also the red button on the remote'],
      ].filter(Boolean);
    }

    function render() {
      var focusedLabel = list.contains(Focus.current) ? Focus.current.dataset.label : null;
      Dom.clear(list);
      rows().forEach((r) => {
        if (r.length === 1) {
          list.appendChild(h('div.settings-heading.vline', { text: r[0] }));
          return;
        }
        var row = h('div.setting.focusable.vline', { data: { label: r[0] } }, [
          h('div.setting-text', [h('div.setting-label', { text: r[0] }), r[3] ? h('div.setting-sub', { text: r[3] }) : null]),
          h('div.setting-value', { text: r[1] }),
        ]);
        row._activate = () => {
          if (!r[2]) return;
          r[2]();
          if (!Overlay.isOpen()) render();
        };
        row.addEventListener('click', row._activate);
        list.appendChild(row);
      });
      var again = focusedLabel && list.querySelector('[data-label="' + focusedLabel + '"]');
      if (again) Focus.set(again, { noScroll: true });
    }

    s.firstFocus = () => list.querySelector('.focusable');
    s.onShow = render;
    // Panels change settings after the row ran; refresh the values when one closes.
    s.refresh = render;
    return s;
  }

  return { create: create };
})();

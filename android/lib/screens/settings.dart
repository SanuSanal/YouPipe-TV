import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/extras.dart';
import '../core/library.dart';
import '../core/settings.dart';
import '../ui/overlay.dart';
import '../ui/theme.dart';

/// Settings: a list; each row opens its choices in a side panel, like YouTube on TV. The same settings as the
/// Samsung app.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _repo = 'SanuSanal/YouPipe-TV';
  static const _qualities = <(Object, String)>[
    ('auto', 'Auto (up to 1080p)'),
    (1080, '1080p'),
    (720, '720p'),
    (480, '480p'),
    (360, '360p'),
  ];
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const _regions = <(String, String)>[
    ('US', 'United States'),
    ('GB', 'United Kingdom'),
    ('IE', 'Ireland'),
    ('IN', 'India'),
    ('CA', 'Canada'),
    ('AU', 'Australia'),
    ('DE', 'Germany'),
    ('FR', 'France'),
    ('ES', 'Spain'),
    ('IT', 'Italy'),
    ('NL', 'Netherlands'),
    ('BR', 'Brazil'),
    ('MX', 'Mexico'),
    ('JP', 'Japan'),
    ('KR', 'South Korea'),
    ('AE', 'United Arab Emirates'),
  ];
  static const _languages = <(String?, String)>[
    (null, 'Same as the TV'),
    ('en', 'English'),
    ('de', 'Deutsch'),
    ('es', 'Español'),
    ('fr', 'Français'),
    ('hi', 'हिन्दी'),
    ('it', 'Italiano'),
    ('ja', '日本語'),
    ('ko', '한국어'),
    ('ml', 'മലയാളം'),
    ('nl', 'Nederlands'),
    ('pt', 'Português'),
    ('ta', 'தமிழ்'),
  ];

  String _version = '';

  @override
  void initState() {
    super.initState();
    Settings.instance.addListener(_changed);
    Library.instance.addListener(_changed);
    // The release workflow passes the version (--dart-define=APP_VERSION).
    _version = const String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
  }

  @override
  void dispose() {
    Settings.instance.removeListener(_changed);
    Library.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _label<T>(List<(T, String)> pairs, T value) => pairs.where((p) => p.$1 == value).firstOrNull?.$2 ?? '$value';

  void _choose<T>(String title, List<(T, String)> pairs, T value, void Function(T) apply) => showPanel(
    context,
    title: title,
    items: [for (final p in pairs) PanelItem(p.$2, checked: p.$1 == value, onSelect: () => apply(p.$1))],
  );

  void _sponsorBlockCategories() {
    final actions = Settings.instance.sbActions;
    showPanel(
      context,
      title: 'SponsorBlock categories',
      subtitle: 'What to do with each kind of segment',
      items: [
        for (final c in SbCategory.all)
          PanelItem(
            c.label,
            color: c.color,
            value: const {'skip': 'Skip', 'show': 'Show on the bar', 'off': 'Off'}[actions[c.key] ?? c.action],
            onSelect: () => _choose<String>(
              c.label,
              const [('skip', 'Skip'), ('show', 'Show on the bar'), ('off', 'Off')],
              actions[c.key] ?? c.action,
              (a) => Settings.instance.set('sbActions', {...Settings.instance.sbActions, c.key: a}),
            ),
          ),
      ],
    );
  }

  Future<void> _checkUpdates() async {
    Toast.show('Checking for updates…');
    try {
      final r = await Dio().get<Map<String, dynamic>>('https://api.github.com/repos/$_repo/releases/latest');
      final latest = (r.data?['tag_name'] as String? ?? '').replaceFirst('v', '');
      if (latest.isEmpty) throw Exception('no release yet');
      if (!mounted) return;
      if (latest == _version) {
        Toast.show('YouPipe is up to date ($_version)');
      } else {
        showConfirm(
          context,
          'Version $latest is available',
          'OK',
          () {},
          detail: 'You have $_version. Install the new APK from sanusanal.github.io/YouPipe-TV',
        );
      }
    } catch (e) {
      Toast.show("Couldn't check for updates: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Settings.instance;
    final lib = Library.instance;
    String onOff(bool v) => v ? 'On' : 'Off';
    final rows = <Object>[
      'Playback',
      PanelItem(
        'Video quality',
        value: _label<Object>(_qualities, s['quality'] ?? 'auto'),
        onSelect: () =>
            _choose<Object>('Video quality', _qualities, s['quality'] ?? 'auto', (v) => s.set('quality', v)),
      ),
      PanelItem('Autoplay next video', value: onOff(s.autoplay), onSelect: () => s.set('autoplay', !s.autoplay)),
      PanelItem(
        'Captions',
        value: onOff(s['captions'] == true),
        onSelect: () => s.set('captions', s['captions'] != true),
      ),
      PanelItem(
        'Caption language',
        value: _label<String?>(_languages, s['captionLang'] as String?),
        onSelect: () => _choose<String?>(
          'Caption language',
          _languages,
          s['captionLang'] as String?,
          (v) => s.set('captionLang', v),
        ),
      ),
      PanelItem(
        'Playback speed',
        value: s.speed == 1 ? 'Normal' : '${s.speed}×',
        onSelect: () => _choose<double>(
          'Playback speed',
          [for (final v in _speeds) (v, v == 1 ? 'Normal' : '$v×')],
          s.speed,
          (v) => s.set('speed', v),
        ),
      ),
      'Extras',
      PanelItem(
        'SponsorBlock: skip sponsors and more',
        sub: 'Community segments from sponsor.ajay.app',
        value: onOff(s.sponsorBlock),
        onSelect: () => s.set('sponsorBlock', !s.sponsorBlock),
      ),
      if (s.sponsorBlock) PanelItem('Categories', onSelect: _sponsorBlockCategories),
      PanelItem(
        'Return YouTube Dislike',
        sub: 'Estimated dislike counts from returnyoutubedislike.com',
        value: onOff(s.dislikes),
        onSelect: () => s.set('dislikes', !s.dislikes),
      ),
      'Content',
      PanelItem(
        'Region',
        sub: 'The country YouTube picks videos for',
        value: _label<String>(_regions, s.gl),
        onSelect: () => _choose<String>('Region', _regions, s.gl, (v) => s.set('gl', v)),
      ),
      PanelItem(
        'Language',
        sub: 'The language of titles and dates from YouTube',
        value: _label<String?>(_languages, s['hl'] as String?),
        onSelect: () => _choose<String?>('Language', _languages, s['hl'] as String?, (v) => s.set('hl', v)),
      ),
      'Privacy',
      PanelItem(
        'Clear watch history',
        value: '${lib.history().length} videos',
        onSelect: () => showConfirm(context, 'Clear watch history?', 'Clear', () => lib.clear('history')),
      ),
      PanelItem(
        'Clear search history',
        value: '${lib.searches().length} searches',
        onSelect: () => showConfirm(context, 'Clear search history?', 'Clear', () => lib.clear('searches')),
      ),
      'About',
      PanelItem('Version', sub: 'Check for updates', value: _version, onSelect: _checkUpdates),
      PanelItem('Source code', value: 'github.com/$_repo'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tv.pad, 120, Tv.pad, 400),
      children: [
        const Text('Settings', style: Tv.pageTitle),
        const SizedBox(height: 32),
        for (final r in rows)
          if (r is String)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 36, 0, 10),
              child: Text(
                r,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: Tv.text2),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: 1120, child: PanelRow(item: r as PanelItem)),
            ),
      ],
    );
  }
}

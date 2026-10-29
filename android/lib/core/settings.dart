import 'package:flutter/foundation.dart';

import 'store.dart';

/// User settings, kept on the TV (`yp.settings`, the same shape as the Samsung app's).
class Settings extends ChangeNotifier {
  Settings._(this._values);

  static late Settings instance;

  static const defaults = <String, Object?>{
    'quality': 'auto', // 'auto' or a maximum height: 1080, 720, 480, 360
    'autoplay': true,
    'captions': false,
    'captionLang': null, // null: the TV's language
    'speed': 1.0,
    'sponsorBlock': false,
    'sbActions': <String, Object?>{}, // category → 'skip' | 'show' | 'off'
    'dislikes': true,
    'gl': 'US',
    'hl': null, // null: the TV's language
  };

  final Map<String, Object?> _values;

  static void init() {
    final saved = Store.instance.get<Map<String, dynamic>>('settings') ?? const {};
    instance = Settings._({...defaults, ...saved});
  }

  Object? operator [](String key) => _values[key];

  void set(String key, Object? value) {
    _values[key] = value;
    Store.instance.set('settings', _values);
    notifyListeners();
  }

  /// The highest height to play: the Video quality setting, at most 1080p.
  int get maxHeight {
    final q = _values['quality'];
    return q is num ? q.toInt() : 1080;
  }

  bool get autoplay => _values['autoplay'] == true;
  bool get sponsorBlock => _values['sponsorBlock'] == true;
  bool get dislikes => _values['dislikes'] == true;
  double get speed => (_values['speed'] as num?)?.toDouble() ?? 1;

  /// The language YouTube answers in: the setting, else the TV's.
  String get hl => (_values['hl'] as String?) ?? PlatformDispatcher.instance.locale.languageCode;
  String get gl => (_values['gl'] as String?) ?? 'US';
  String get captionLang => (_values['captionLang'] as String?) ?? PlatformDispatcher.instance.locale.languageCode;

  Map<String, String> get sbActions => {
    for (final e in ((_values['sbActions'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
  };
}

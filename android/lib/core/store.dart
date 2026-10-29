import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything the app keeps lives on the TV, as JSON in shared preferences under `yp.<key>` (docs/data.md), the same
/// keys and shapes as the Samsung app's localStorage.
class Store {
  Store._(this._prefs);

  static late Store instance;

  final SharedPreferences _prefs;

  static Future<void> init() async => instance = Store._(await SharedPreferences.getInstance());

  T? get<T>(String key) {
    final raw = _prefs.getString('yp.$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as T?;
    } catch (e) {
      debugPrint('YouPipe: store $key unreadable: $e');
      return null;
    }
  }

  Future<void> set(String key, Object? value) => _prefs.setString('yp.$key', jsonEncode(value));
}

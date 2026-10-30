import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'store.dart';

/// Update checks (docs/release.md): the latest GitHub release, at most once a day after Home loads, and whenever
/// Settings → Version asks. `yp.updates` keeps `{checkedAt, latest, notified}`, the same as the Samsung app.
abstract final class Updates {
  static const repo = 'SanuSanal/YouPipe-TV';

  /// This build's version, from the release workflow; local builds are 'dev' and never check by themselves.
  static const version = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  /// A newer version than this one, once a check has found it.
  static final available = ValueNotifier<String?>(null);

  static Map<String, dynamic> get _saved => Store.instance.get<Map<String, dynamic>>('updates') ?? const {};

  /// Loads what the last check found.
  static void init() {
    final latest = _saved['latest'] as String?;
    if (latest != null && isNewer(latest, version)) available.value = latest;
  }

  /// The latest release's version; a daily check answers from the last one when it ran less than a day ago.
  static Future<String> check({bool force = false}) async {
    final saved = _saved;
    final at = DateTime.fromMillisecondsSinceEpoch((saved['checkedAt'] as num?)?.toInt() ?? 0);
    var latest = saved['latest'] as String?;
    if (force || latest == null || DateTime.now().difference(at) > const Duration(days: 1)) {
      final r = await Dio().get<Map<String, dynamic>>('https://api.github.com/repos/$repo/releases/latest');
      latest = (r.data?['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), '');
      if (latest.isEmpty) throw Exception('no release yet');
      await Store.instance.set('updates', {
        ...saved,
        'checkedAt': DateTime.now().millisecondsSinceEpoch,
        'latest': latest,
      });
    }
    available.value = isNewer(latest, version) ? latest : null;
    return latest;
  }

  /// A newer version the start-up prompt hasn't offered yet; each is offered once ([offered]).
  static Future<String?> toOffer() async {
    if (version == 'dev') return null;
    final latest = await check();
    return isNewer(latest, version) && _saved['notified'] != latest ? latest : null;
  }

  static Future<void> offered(String latest) => Store.instance.set('updates', {..._saved, 'notified': latest});

  /// Whether version [a] is newer than [b] (MAJOR.MINOR.PATCH); a 'dev' build counts as older than any release.
  static bool isNewer(String a, String b) {
    List<int> parts(String v) => v.split('.').map((p) => int.tryParse(p) ?? -1).toList();
    final x = parts(a), y = parts(b);
    if (x.any((p) => p < 0)) return false;
    if (y.any((p) => p < 0)) return true;
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d > 0;
    }
    return false;
  }

  /// The release's APK for this TV: the per-ABI one when there is one, else the one with every ABI (docs/release.md).
  static String apkUrl(String version, String abi) {
    const split = {'arm64-v8a', 'armeabi-v7a'};
    final name = 'YouPipe-TV-v$version-${split.contains(abi) ? abi : 'android'}.apk';
    return 'https://github.com/$repo/releases/download/v$version/$name';
  }
}

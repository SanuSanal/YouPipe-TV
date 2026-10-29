import 'dart:convert';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'settings.dart';

/// A SponsorBlock category with its community-standard colour and default action (as in YouPipe and the Samsung app).
class SbCategory {
  const SbCategory(this.key, this.label, this.color, this.action);

  final String key;
  final String label;
  final Color color;
  final String action;

  static const all = [
    SbCategory('sponsor', 'Sponsor', Color(0xFF00D400), 'skip'),
    SbCategory('selfpromo', 'Self promotion', Color(0xFFFFFF00), 'skip'),
    SbCategory('interaction', 'Interaction reminder', Color(0xFFCC00FF), 'skip'),
    SbCategory('intro', 'Intro', Color(0xFF00FFFF), 'show'),
    SbCategory('outro', 'Endcards and credits', Color(0xFF0202ED), 'show'),
    SbCategory('preview', 'Preview and recap', Color(0xFF008FD6), 'show'),
    SbCategory('filler', 'Filler tangent', Color(0xFF7300FF), 'off'),
    SbCategory('music_offtopic', 'Non-music section', Color(0xFFFF9900), 'skip'),
  ];

  String get currentAction {
    final s = Settings.instance;
    if (!s.sponsorBlock) return 'off';
    return s.sbActions[key] ?? action;
  }
}

class SbSegment {
  const SbSegment(this.category, this.start, this.end);

  final SbCategory category;
  final Duration start;
  final Duration end;
}

final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 10)));

/// SponsorBlock segments: uses the hash-prefix endpoint, so only the first 4 hex characters of sha256(videoId) leave
/// the TV. Off unless the user turns it on.
abstract final class SponsorBlock {
  static final _cache = <String, List<SbSegment>>{};

  static Future<List<SbSegment>> segments(String videoId) async {
    if (!Settings.instance.sponsorBlock) return const [];
    var all = _cache[videoId];
    if (all == null) {
      final prefix = sha256.convert(utf8.encode(videoId)).toString().substring(0, 4);
      try {
        final res = await _dio.get<List<dynamic>>(
          'https://sponsor.ajay.app/api/skipSegments/$prefix',
          queryParameters: {
            'categories': jsonEncode([for (final c in SbCategory.all) c.key]),
            'actionType': 'skip',
          },
        );
        final entry = (res.data ?? const []).whereType<Map>().where((e) => e['videoID'] == videoId).firstOrNull;
        final byKey = {for (final c in SbCategory.all) c.key: c};
        all = [
          for (final s in (entry?['segments'] as List? ?? const []).whereType<Map>())
            if ((s['segment'], byKey[s['category']]) case ([final num start, final num end], final SbCategory c)
                when end - start >= 1)
              SbSegment(
                c,
                Duration(milliseconds: (start * 1000).round()),
                Duration(milliseconds: (end * 1000).round()),
              ),
        ]..sort((a, b) => a.start.compareTo(b.start));
      } on DioException catch (e) {
        // 404: no segments for any video with this prefix.
        if (e.response?.statusCode != 404) {
          debugPrint('YouPipe: SponsorBlock failed: $e');
          return const [];
        }
        all = const [];
      }
      _cache[videoId] = all;
    }
    return all.where((s) => s.category.currentAction != 'off').toList();
  }
}

/// Estimated dislikes from Return YouTube Dislike (returnyoutubedislikeapi.com).
abstract final class Dislikes {
  static final _cache = <String, int?>{};

  static Future<int?> count(String videoId) async {
    if (!Settings.instance.dislikes) return null;
    if (_cache.containsKey(videoId)) return _cache[videoId];
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://returnyoutubedislikeapi.com/votes',
        queryParameters: {'videoId': videoId},
      );
      return _cache[videoId] = (res.data?['dislikes'] as num?)?.toInt();
    } catch (e) {
      debugPrint('YouPipe: Return YouTube Dislike failed: $e');
      return null;
    }
  }
}

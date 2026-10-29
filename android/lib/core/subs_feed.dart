import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../innertube/innertube.dart';
import 'format.dart';
import 'library.dart';
import 'services.dart';
import 'store.dart';

/// A subscription upload with its date.
class FeedVideo {
  const FeedVideo(this.video, this.publishedAt);

  final VideoItem video;
  final DateTime publishedAt;
}

/// The subscriptions feed without an account (docs/data.md): each subscribed channel's latest uploads, newest first,
/// cached on the TV (`yp.subsFeed`, as in the Samsung app) and refreshed at most every 30 minutes.
/// - First the channel's Atom feed (feeds/videos.xml, the 15 latest uploads with exact dates);
/// - when that fails (YouTube answers 404 for some channels), its Videos tab through InnerTube, with relative dates.
abstract final class SubsFeed {
  static const _minInterval = Duration(minutes: 30);
  static const _videosTab = 'EgZ2aWRlb3PyBgQKAjoA';
  static final _dio = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 20)));
  static Future<List<FeedVideo>>? _running;

  static Map<String, dynamic> _cached() =>
      Store.instance.get<Map<String, dynamic>>('subsFeed') ?? {'at': 0, 'videos': <dynamic>[]};

  /// The cached feed, newest first, without Shorts.
  static List<FeedVideo> videos() {
    final subs = {for (final s in Library.instance.subscriptions()) s.id: s};
    final out = <FeedVideo>[];
    for (final j in (_cached()['videos'] as List? ?? const [])) {
      final v = itemFromJson(j);
      final at = (j is Map ? j['publishedAt'] as num? : null)?.toInt();
      if (v is! VideoItem || at == null || v.isShort) continue;
      final channel = subs[v.channelId];
      if (channel == null) continue;
      final when = DateTime.fromMillisecondsSinceEpoch(at);
      out.add(
        FeedVideo(
          VideoItem(
            id: v.id,
            title: v.title,
            channelName: v.channelName ?? channel.name,
            channelId: v.channelId,
            channelAvatar: channel.avatar,
            thumbnail: v.thumbnail,
            viewsText: v.viewsText,
            publishedText: timeAgo(when),
          ),
          when,
        ),
      );
    }
    return out;
  }

  static Future<List<FeedVideo>> refresh({bool force = false}) {
    final at = (_cached()['at'] as num?)?.toInt() ?? 0;
    if (!force && DateTime.now().millisecondsSinceEpoch - at < _minInterval.inMilliseconds) {
      return Future.value(videos());
    }
    return _running ??= _refresh().whenComplete(() => _running = null);
  }

  static Future<List<FeedVideo>> _refresh() async {
    final subs = Library.instance.subscriptions();
    final collected = <Map<String, Object?>>[];
    final fetched = <String>{};
    var next = 0;
    Future<void> worker() async {
      while (next < subs.length) {
        final s = subs[next++];
        try {
          collected.addAll(await latest(s));
          fetched.add(s.id);
        } catch (e) {
          debugPrint('YouPipe: feed ${s.name} failed: $e');
        }
      }
    }

    await Future.wait([for (var i = 0; i < 6; i++) worker()]);
    // Keep what an unreachable channel had before.
    final kept = (_cached()['videos'] as List? ?? const []).whereType<Map>().where(
      (j) => !fetched.contains(j['channelId']),
    );
    _save([...collected, for (final k in kept) k.cast<String, Object?>()]);
    return videos();
  }

  static void _save(List<Map<String, Object?>> all) {
    final cutoff = DateTime.now().subtract(const Duration(days: 60)).millisecondsSinceEpoch;
    final byId = <String, Map<String, Object?>>{};
    for (final v in all) {
      if (((v['publishedAt'] as num?) ?? 0) >= cutoff) byId[v['id'] as String] = v;
    }
    final list = byId.values.toList()..sort((a, b) => (b['publishedAt'] as num).compareTo(a['publishedAt'] as num));
    Store.instance.set('subsFeed', {'at': DateTime.now().millisecondsSinceEpoch, 'videos': list.take(600).toList()});
  }

  /// Fetches one channel right after subscribing.
  static Future<void> refreshChannel(ChannelItem c) async {
    try {
      final videos = await latest(c);
      final old = (_cached()['videos'] as List? ?? const []).whereType<Map>().map((m) => m.cast<String, Object?>());
      _save([...videos, ...old]);
    } catch (e) {
      debugPrint('YouPipe: feed ${c.name} failed: $e');
    }
  }

  /// A channel's latest uploads as stored JSON (item fields plus `publishedAt`).
  static Future<List<Map<String, Object?>>> latest(ChannelItem c) async {
    try {
      final res = await _dio.get<String>(
        'https://www.youtube.com/feeds/videos.xml',
        queryParameters: {'channel_id': c.id},
        options: Options(responseType: ResponseType.plain),
      );
      final entries = parseAtom(res.data ?? '', c);
      if (entries.isNotEmpty) return entries;
    } catch (_) {
      // Fall through to the Videos tab.
    }
    final page = await Services.yt.channel(c.id, params: _videosTab);
    return [
      for (final v in page.content.entries.allItems.whereType<VideoItem>().take(15))
        {
          ...itemToJson(v),
          'channel': v.channelName ?? c.name,
          'channelId': c.id,
          'publishedAt': _approxDate(v.publishedText).millisecondsSinceEpoch,
        },
    ];
  }

  static List<Map<String, Object?>> parseAtom(String xml, ChannelItem c) {
    final doc = XmlDocument.parse(xml);
    return [
      for (final e in doc.findAllElements('entry'))
        if (e.getElement('yt:videoId')?.innerText case final id?)
          {
            'type': 'video',
            'id': id,
            'title': e.getElement('title')?.innerText ?? '',
            'channel': e.getElement('author')?.getElement('name')?.innerText ?? c.name,
            'channelId': c.id,
            'thumb': 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
            'views': switch (int.tryParse(
              e
                      .getElement('media:group')
                      ?.getElement('media:community')
                      ?.getElement('media:statistics')
                      ?.getAttribute('views') ??
                  '',
            )) {
              final n? => viewsLabel(n),
              null => null,
            },
            'publishedAt': (DateTime.tryParse(e.getElement('published')?.innerText ?? '') ?? DateTime.now())
                .millisecondsSinceEpoch,
            'short': e.getElement('link')?.getAttribute('href')?.contains('/shorts/') ?? false,
          },
    ];
  }

  /// "3 days ago" → about then, so tab results sort with feed results.
  static DateTime _approxDate(String? text) {
    final m = RegExp(r'(\d+)\s+(second|minute|hour|day|week|month|year)').firstMatch(text ?? '');
    if (m == null) return DateTime.now().subtract(const Duration(days: 365));
    const unit = {
      'second': 1,
      'minute': 60,
      'hour': 3600,
      'day': 86400,
      'week': 604800,
      'month': 2592000,
      'year': 31536000,
    };
    return DateTime.now().subtract(Duration(seconds: int.parse(m[1]!) * unit[m[2]]!));
  }
}

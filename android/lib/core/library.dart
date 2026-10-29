import 'package:flutter/foundation.dart';

import '../innertube/models.dart';
import 'store.dart';

/// One watch history entry: where the video got to.
class HistoryEntry {
  const HistoryEntry(this.video, this.position, this.duration, this.at);

  final VideoItem video;
  final int position;
  final int duration;
  final int at;

  double get progress => duration > 0 ? position / duration : 0;

  Map<String, Object?> toJson() => {'video': itemToJson(video), 'position': position, 'duration': duration, 'at': at};

  static HistoryEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final v = itemFromJson(j['video']);
    if (v is! VideoItem) return null;
    return HistoryEntry(
      v,
      (j['position'] as num?)?.toInt() ?? 0,
      (j['duration'] as num?)?.toInt() ?? 0,
      (j['at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Items in the Samsung app's JSON shape (`{type, id, title, channel, …}`), so both apps keep the same data.
Map<String, Object?> itemToJson(YtItem item) => switch (item) {
  VideoItem v => {
    'type': 'video',
    'id': v.id,
    'title': v.title,
    'channel': v.channelName,
    'channelId': v.channelId,
    'avatar': v.channelAvatar,
    'thumb': v.thumbnail,
    'duration': v.durationText,
    'views': v.viewsText,
    'published': v.publishedText,
    'live': v.isLive,
    'short': v.isShort,
  },
  ChannelItem c => {'type': 'channel', 'id': c.id, 'name': c.name, 'avatar': c.avatar, 'subs': c.subscribersText},
  PlaylistItem p => {
    'type': 'playlist',
    'id': p.id,
    'title': p.title,
    'thumb': p.thumbnail,
    'channel': p.channelName,
    'count': p.countText,
  },
};

YtItem? itemFromJson(Object? j) {
  if (j is! Map || j['id'] is! String) return null;
  final id = j['id'] as String;
  switch (j['type']) {
    case 'channel':
      return ChannelItem(
        id: id,
        name: j['name'] as String? ?? '',
        avatar: j['avatar'] as String?,
        subscribersText: j['subs'] as String?,
      );
    case 'playlist':
      return PlaylistItem(
        id: id,
        title: j['title'] as String? ?? '',
        thumbnail: j['thumb'] as String?,
        channelName: j['channel'] as String?,
        countText: j['count'] as String?,
      );
    default:
      return VideoItem(
        id: id,
        title: j['title'] as String? ?? '',
        channelName: j['channel'] as String?,
        channelId: j['channelId'] as String?,
        channelAvatar: j['avatar'] as String?,
        thumbnail: j['thumb'] as String?,
        durationText: j['duration'] as String?,
        viewsText: j['views'] as String?,
        publishedText: j['published'] as String?,
        isLive: j['live'] == true,
        isShort: j['short'] == true,
      );
  }
}

/// The user's library, kept on the TV (docs/data.md): watch history with progress, subscriptions, Watch later, liked
/// videos, saved playlists and search history. Nothing leaves the TV.
class Library extends ChangeNotifier {
  Library._();

  static final instance = Library._();

  static const _limits = {
    'history': 500,
    'watchLater': 500,
    'liked': 1000,
    'playlists': 200,
    'subs': 2000,
    'searches': 30,
  };

  List<YtItem> listOf(String key) => [
    for (final j in Store.instance.get<List<dynamic>>(key) ?? const []) ?itemFromJson(j),
  ];

  void _save(String key, List<Object?> list) {
    Store.instance.set(key, list.take(_limits[key] ?? 500).toList());
    notifyListeners();
  }

  bool has(String key, String id) => listOf(key).any((i) => i.id == id);

  /// Adds or removes; true when it's now in the list.
  bool toggle(String key, YtItem item) {
    final list = listOf(key);
    final had = list.any((i) => i.id == item.id);
    final next = had ? list.where((i) => i.id != item.id).toList() : [item, ...list];
    _save(key, next.map(itemToJson).toList());
    return !had;
  }

  void remove(String key, String id) {
    if (key == 'history') {
      _save(key, history().where((h) => h.video.id != id).map((h) => h.toJson()).toList());
    } else {
      _save(key, listOf(key).where((i) => i.id != id).map(itemToJson).toList());
    }
  }

  void clear(String key) => _save(key, const []);

  // History ---------------------------------------------------------------------------------------------------------

  List<HistoryEntry> history() => [
    for (final j in Store.instance.get<List<dynamic>>('history') ?? const []) ?HistoryEntry.fromJson(j),
  ];

  HistoryEntry? progress(String id) => history().where((h) => h.video.id == id).firstOrNull;

  void saveProgress(VideoItem video, int position, int duration) {
    final entry = HistoryEntry(video, position, duration, DateTime.now().millisecondsSinceEpoch);
    _save('history', [entry.toJson(), ...history().where((h) => h.video.id != video.id).map((h) => h.toJson())]);
  }

  /// Videos started but not finished, newest first.
  List<HistoryEntry> continueWatching() => history()
      .where((h) => !h.video.isLive && h.duration > 60 && h.position > 15 && h.position < h.duration * 0.9)
      .toList();

  // Subscriptions ---------------------------------------------------------------------------------------------------

  List<ChannelItem> subscriptions() => listOf('subs').whereType<ChannelItem>().toList();

  bool isSubscribed(String channelId) => has('subs', channelId);

  /// Subscribes or unsubscribes; true when now subscribed.
  bool toggleSubscription(ChannelItem channel) => toggle('subs', channel);

  // Searches --------------------------------------------------------------------------------------------------------

  List<String> searches() => [for (final s in Store.instance.get<List<dynamic>>('searches') ?? const []) '$s'];

  void addSearch(String q) {
    q = q.trim();
    if (q.isEmpty) return;
    _save('searches', [q, ...searches().where((s) => s.toLowerCase() != q.toLowerCase())]);
  }
}

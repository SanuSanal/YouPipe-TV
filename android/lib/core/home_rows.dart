import 'dart:math';

import '../innertube/innertube.dart';
import 'library.dart';
import 'services.dart';
import 'subs_feed.dart';

/// A Home row: where its videos come from. [load] gives the first page; [more] the next ones (empty when done).
class RowSource {
  RowSource(this.title, this.load, {this.more});

  final String title;
  final Future<List<YtItem>> Function() load;
  final Future<List<YtItem>> Function()? more;
}

/// The Home rows. Signed out, YouTube's own Home is empty until it has watch history, so like YouPipe and the Samsung
/// app the rows are built on the TV (docs/data.md): continue watching, recommendations from what was watched
/// (related videos), new uploads from subscriptions, then topic rows from searches of this week's videos.
abstract final class HomeRows {
  static const _thisWeekVideos = 'EgQIAxAB';
  static const _live = 'EgJAAQ%3D%3D';
  static const _topics = [
    ('Gaming', 'gaming'),
    ('News', 'news today'),
    ('Sports', 'sports highlights'),
    ('Comedy', 'comedy'),
    ('Science and tech', 'science technology'),
    ('Cooking', 'cooking recipes'),
    ('Podcasts', 'podcast'),
    ('Travel', 'travel vlog'),
  ];

  /// Long videos only: no Shorts on the TV's Home.
  static List<YtItem> _playable(Iterable<YtItem> items) => [
    for (final i in items)
      if (i is VideoItem && !i.isShort) i,
  ];

  static RowSource _search(String title, String query, String params) {
    String? token;
    return RowSource(
      title,
      () async {
        final p = await Services.yt.search(query, params: params);
        token = p.continuation;
        return _playable(p.entries.allItems);
      },
      more: () async {
        final t = token;
        if (t == null) return const [];
        final p = await Services.yt.searchContinuation(t);
        token = p.continuation;
        return _playable(p.entries.allItems);
      },
    );
  }

  /// Related videos of several seeds, interleaved; finished videos are left out.
  static RowSource _related(String title, List<String> seeds, Set<String> exclude) {
    var tokens = <String>[];
    final seen = <String>{};
    List<YtItem> fresh(List<List<YtItem>> lists) {
      final out = <YtItem>[];
      for (var i = 0; lists.any((l) => i < l.length); i++) {
        for (final l in lists) {
          if (i < l.length) out.add(l[i]);
        }
      }
      return _playable(out).where((v) => !exclude.contains(v.id) && seen.add(v.id)).toList();
    }

    Future<List<YtItem>> run(Future<Paged<YtItem>> Function(String) fetch, List<String> keys) async {
      final pages = await Future.wait(keys.map((k) => fetch(k).then<Paged<YtItem>?>((p) => p, onError: (_) => null)));
      final ok = pages.whereType<Paged<YtItem>>().toList();
      tokens = [for (final p in ok) ?p.continuation];
      return fresh([for (final p in ok) p.items]);
    }

    return RowSource(
      title,
      () => run(Services.yt.related, seeds),
      more: () => tokens.isEmpty ? Future.value(const []) : run(Services.yt.nextContinuation, tokens),
    );
  }

  static List<RowSource> sources() {
    final lib = Library.instance;
    final out = <RowSource>[];
    final cw = lib.continueWatching();
    if (cw.isNotEmpty) out.add(RowSource('Continue watching', () async => [for (final h in cw.take(30)) h.video]));
    final history = lib.history();
    final finished = {
      for (final h in history)
        if (h.duration > 0 && h.position > h.duration * 0.9) h.video.id,
    };
    final seeds = [
      for (final h in history)
        if (!h.video.isShort) h.video.id,
    ].take(6).toList();
    if (seeds.isNotEmpty) out.add(_related('Recommended', seeds, finished));
    if (lib.subscriptions().isNotEmpty) {
      out.add(
        RowSource('Latest from your subscriptions', () async {
          final cached = SubsFeed.videos();
          final fresh = SubsFeed.refresh();
          return [for (final f in (cached.isNotEmpty ? cached : await fresh).take(40)) f.video];
        }),
      );
    }
    if (history.isNotEmpty) {
      out.add(_related('Because you watched ${history.first.video.title}', [history.first.video.id], finished));
    }
    out.add(_search('Music', 'music', _thisWeekVideos));
    out.add(_search('Live now', 'live', _live));
    for (final t in [..._topics]..shuffle(Random())) {
      out.add(_search(t.$1, t.$2, _thisWeekVideos));
    }
    return out;
  }
}

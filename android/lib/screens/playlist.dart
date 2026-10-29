import 'dart:math';

import 'package:flutter/material.dart';

import '../core/library.dart';
import '../core/services.dart';
import '../innertube/innertube.dart';
import '../ui/actions.dart';
import '../ui/cards.dart';
import '../ui/focusable.dart';
import '../ui/overlay.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';
import 'watch.dart';

/// A playlist: its details and Play all / Shuffle / Save on the left, the videos as a list on the right.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlist});

  final PlaylistItem playlist;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  PlaylistPage? _page;
  Object? _error;
  List<VideoItem> _videos = const [];
  String? _token;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Services.yt.playlist(widget.playlist.id);
      if (!mounted) return;
      setState(() {
        _page = p;
        _videos = p.videos.items.whereType<VideoItem>().toList();
        _token = p.videos.continuation;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<List<VideoItem>> _more() async {
    final t = _token;
    if (t == null || _loadingMore) return const [];
    _loadingMore = true;
    try {
      final p = await Services.yt.browseContinuation(t);
      final more = p.entries.allItems.whereType<VideoItem>().toList();
      if (mounted) {
        setState(() {
          _token = p.continuation;
          _videos = [..._videos, ...more];
        });
      }
      return more;
    } finally {
      _loadingMore = false;
    }
  }

  PlayQueue _queue(int index, {bool shuffle = false}) {
    final items = [..._videos];
    if (shuffle) items.shuffle(Random());
    return PlayQueue(
      items,
      shuffle ? 0 : index,
      title: _page?.title ?? widget.playlist.title,
      more: shuffle ? null : _more,
    );
  }

  void _play(int index, {bool shuffle = false}) {
    if (_videos.isEmpty) return;
    final q = _queue(index, shuffle: shuffle);
    WatchScreen.open(context, q.items[q.index], queue: q);
  }

  @override
  Widget build(BuildContext context) {
    final p = _page;
    final saved = Library.instance.has('playlists', widget.playlist.id);
    return Material(
      color: Tv.bg,
      child: TvKeys(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 580,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Tv.pad, 72, 48, 0),
                child: _error != null
                    ? Text("Couldn't load this playlist: $_error", style: const TextStyle(fontSize: 26))
                    : p == null
                    ? const Text('Loading…', style: TextStyle(fontSize: 26, color: Tv.text2))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: NetImage(p.thumbnail ?? widget.playlist.thumbnail, width: 468),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            p.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            p.owner ?? widget.playlist.channelName ?? '',
                            style: const TextStyle(fontSize: 26, color: Color(0xFFDDDDDD)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            p.metadata.where((m) => m != 'Playlist').join(' • '),
                            style: const TextStyle(fontSize: 22, color: Tv.text2),
                          ),
                          const SizedBox(height: 40),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              TvButton(
                                label: 'Play all',
                                icon: Icons.play_arrow,
                                autofocus: true,
                                onSelect: () => _play(0),
                              ),
                              TvButton(label: 'Shuffle', icon: Icons.shuffle, onSelect: () => _play(0, shuffle: true)),
                              TvButton(
                                label: saved ? 'Saved' : 'Save',
                                icon: Icons.playlist_add,
                                onSelect: () {
                                  final now = Library.instance.toggle(
                                    'playlists',
                                    PlaylistItem(
                                      id: widget.playlist.id,
                                      title: p.title,
                                      thumbnail: p.thumbnail ?? widget.playlist.thumbnail,
                                      channelName: p.owner,
                                      countText: widget.playlist.countText,
                                    ),
                                  );
                                  setState(() {});
                                  Toast.show(now ? 'Saved to Library' : 'Removed from Library');
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(0, 48, Tv.pad, 48),
                itemCount: _videos.length,
                itemBuilder: (context, i) {
                  final v = _videos[i];
                  if (i >= _videos.length - 8) _more();
                  return TvFocusable(
                    scrollAlignment: 0.4,
                    onSelect: () => _play(i),
                    onLongPress: () => itemOptions(context, v),
                    builder: (context, focused) => Container(
                      padding: const EdgeInsets.fromLTRB(8, 12, 20, 12),
                      decoration: BoxDecoration(
                        color: focused ? const Color(0x1FFFFFFF) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(
                              '${i + 1}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 22, color: Tv.text2),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: focused ? const [BoxShadow(color: Colors.white, spreadRadius: 4)] : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 256,
                                height: 144,
                                child: NetImage(v.thumbnailOrDefault, width: 256),
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tv.cardTitle),
                                Text(
                                  [v.channelName, v.viewsText].whereType<String>().join(' • '),
                                  maxLines: 1,
                                  style: Tv.cardMeta,
                                ),
                              ],
                            ),
                          ),
                          if (v.durationText != null) Text(v.durationText!, style: Tv.cardMeta),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

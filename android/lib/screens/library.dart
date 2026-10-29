import 'dart:async';

import 'package:flutter/material.dart';

import '../core/account.dart';
import '../core/library.dart';
import '../core/services.dart';
import '../innertube/innertube.dart';
import '../ui/actions.dart';
import '../ui/cards.dart';
import '../ui/overlay.dart';
import '../ui/theme.dart';
import 'playlist.dart';
import 'subscriptions.dart';

/// Library: history, Watch later, liked videos, saved playlists and subscriptions, each a row, kept on the TV. Signed
/// in, the account's YouTube history, Watch later, liked videos and playlists come after the TV's history.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _rowLimit = 20;

  /// The account's lists: title, items, and the playlist that shows all of it (null: the row holds all there is).
  List<(String, List<YtItem>, PlaylistItem?)> _account = const [];
  Timer? _reload;

  @override
  void initState() {
    super.initState();
    Library.instance.addListener(_changed);
    Account.instance.addListener(_loadAccount);
    _loadAccount();
  }

  @override
  void dispose() {
    Library.instance.removeListener(_changed);
    Account.instance.removeListener(_loadAccount);
    _reload?.cancel();
    super.dispose();
  }

  /// A change here may have gone to the account too (Watch later, likes), so its lists reload shortly after.
  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (Account.instance.signedIn) {
      _reload?.cancel();
      _reload = Timer(const Duration(seconds: 3), _loadAccount);
    }
  }

  Future<void> _loadAccount() async {
    if (!Account.instance.signedIn) {
      if (mounted && _account.isNotEmpty) setState(() => _account = const []);
      return;
    }
    final yt = Services.yt;
    Future<List<YtItem>> safe(Future<List<YtItem>> f) => f.catchError((Object e) {
      debugPrint('YouPipe: account list failed: $e');
      return const <YtItem>[];
    });
    final lists = await Future.wait([
      safe(yt.accountFeed('FEhistory').then((p) => p.entries.allItems.whereType<VideoItem>().toList())),
      safe(yt.playlist('WL').then((p) => p.videos.items)),
      safe(yt.playlist('LL').then((p) => p.videos.items)),
      safe(yt.accountFeed('FEplaylist_aggregation').then((p) => p.entries.allItems.whereType<PlaylistItem>().toList())),
    ]);
    if (!mounted || !Account.instance.signedIn) return;
    setState(
      () => _account = [
        ('YouTube history', lists[0], null),
        ('YouTube Watch later', lists[1], const PlaylistItem(id: 'WL', title: 'Watch later')),
        ('YouTube liked videos', lists[2], const PlaylistItem(id: 'LL', title: 'Liked videos')),
        ('YouTube playlists', lists[3], null),
      ],
    );
  }

  /// Card actions that add "Remove from …" for the list the card sits in.
  ItemActions _actions(String key, String title) => defaultActions(
    context,
    extra: (item) => [
      PanelItem('Remove from $title', icon: Icons.close, onSelect: () => Library.instance.remove(key, item.id)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final lib = Library.instance;
    final sections = <(String, List<YtItem>, String?)>[
      ('History', [for (final h in lib.history()) h.video], 'history'),
      for (final a in _account) (a.$1, a.$2, null),
      ('Watch later', lib.listOf('watchLater'), 'watchLater'),
      ('Liked videos', lib.listOf('liked'), 'liked'),
      ('Saved playlists', lib.listOf('playlists'), 'playlists'),
      ('Subscriptions', lib.subscriptions(), null),
    ].where((s) => s.$2.isNotEmpty).toList();
    if (sections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(Tv.pad, 152, Tv.pad, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your library is empty', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w500)),
            SizedBox(height: 16),
            Text(
              'Videos you watch, save for later or like, and playlists you save, show up here.',
              style: TextStyle(fontSize: 26, color: Tv.text2),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tv.pad, Tv.topbarHeight, 0, 600),
      children: [
        for (final s in sections)
          TvRow(
            key: ValueKey(s.$1),
            title: s.$1,
            items: s.$2.take(_rowLimit).toList(),
            actions: s.$3 == null ? defaultActions(context) : _actions(s.$3!, s.$1),
          ),
        // Longer lists open in full from here.
        if (sections.any((s) => s.$2.length > _rowLimit)) ...[
          const SizedBox(height: 8),
          for (final s in sections.where((s) => s.$2.length > _rowLimit))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _SeeAll(
                title: s.$1,
                items: s.$2,
                actions: s.$3 == null ? null : _actions(s.$3!, s.$1),
                playlist: _account.where((a) => a.$1 == s.$1).firstOrNull?.$3,
              ),
            ),
        ],
      ],
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.title, required this.items, this.actions, this.playlist});

  final String title;
  final List<YtItem> items;
  final ItemActions? actions;

  /// An account list that pages in full from its playlist (Watch later, liked videos).
  final PlaylistItem? playlist;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: PanelRow(
      item: PanelItem('See all: $title', value: playlist == null ? '${items.length}' : null, icon: Icons.grid_view),
      onSelect: () => Navigator.of(context).push(
        tvRoute(
          playlist != null
              ? PlaylistScreen(playlist: playlist!)
              : ListScreen(title: title, items: items, actions: actions),
        ),
      ),
    ),
  );
}

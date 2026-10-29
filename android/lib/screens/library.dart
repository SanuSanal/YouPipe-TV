import 'package:flutter/material.dart';

import '../core/library.dart';
import '../innertube/innertube.dart';
import '../ui/actions.dart';
import '../ui/cards.dart';
import '../ui/overlay.dart';
import '../ui/theme.dart';
import 'subscriptions.dart';

/// Library: history, Watch later, liked videos, saved playlists and subscriptions, each a row; all kept on the TV.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _rowLimit = 20;

  @override
  void initState() {
    super.initState();
    Library.instance.addListener(_changed);
  }

  @override
  void dispose() {
    Library.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
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
      padding: const EdgeInsets.fromLTRB(Tv.pad, 56, 0, 600),
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
              child: _SeeAll(title: s.$1, items: s.$2, actions: s.$3 == null ? null : _actions(s.$3!, s.$1)),
            ),
        ],
      ],
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.title, required this.items, this.actions});

  final String title;
  final List<YtItem> items;
  final ItemActions? actions;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: PanelRow(
      item: PanelItem('See all: $title', value: '${items.length}', icon: Icons.grid_view),
      onSelect: () => Navigator.of(context).push(tvRoute(ListScreen(title: title, items: items, actions: actions))),
    ),
  );
}

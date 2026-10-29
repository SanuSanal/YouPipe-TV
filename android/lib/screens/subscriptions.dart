import 'package:flutter/material.dart';

import '../core/library.dart';
import '../core/subs_feed.dart';
import '../innertube/innertube.dart';
import '../ui/actions.dart';
import '../ui/cards.dart';
import '../ui/focusable.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';

/// Subscriptions: the subscribed channels in a row, then their latest videos in a grid (core/subs_feed.dart).
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  List<FeedVideo> _videos = SubsFeed.videos();
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    Library.instance.addListener(_onLibrary);
    _refresh();
  }

  @override
  void dispose() {
    Library.instance.removeListener(_onLibrary);
    super.dispose();
  }

  void _onLibrary() {
    if (mounted) setState(() => _videos = SubsFeed.videos());
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final v = await SubsFeed.refresh();
      if (mounted) setState(() => _videos = v);
    } catch (e) {
      debugPrint('YouPipe: subscriptions refresh failed: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = Library.instance.subscriptions();
    if (subs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Tv.pad, 152, Tv.pad, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No subscriptions yet', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            const Text(
              'Open a channel and choose Subscribe. Its new videos show up here.',
              style: TextStyle(fontSize: 26, color: Tv.text2),
            ),
            const SizedBox(height: 36),
            TvButton(
              label: 'Search',
              icon: Icons.search,
              onSelect: () => context.findAncestorStateOfType<ShellState>()?.open('search'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tv.pad, 56, Tv.pad, 400),
      children: [
        TvRow(title: 'Channels', items: subs, actions: defaultActions(context)),
        Text(_videos.isEmpty && _refreshing ? 'Loading videos…' : 'Latest videos', style: Tv.rowTitle),
        const SizedBox(height: 14),
        TvGrid(items: [for (final f in _videos) f.video], actions: defaultActions(context)),
      ],
    );
  }
}

/// A titled grid of items: Library's "See all".
class ListScreen extends StatelessWidget {
  const ListScreen({super.key, required this.title, required this.items, this.actions});

  final String title;
  final List<YtItem> items;
  final ItemActions? actions;

  @override
  Widget build(BuildContext context) => Material(
    color: Tv.bg,
    child: TvKeys(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Tv.pad + Tv.navWidth, 140, Tv.pad, 400),
        children: [
          Text(title, style: Tv.pageTitle),
          const SizedBox(height: 32),
          TvGrid(items: items, autofocus: true, actions: actions ?? defaultActions(context)),
        ],
      ),
    ),
  );
}

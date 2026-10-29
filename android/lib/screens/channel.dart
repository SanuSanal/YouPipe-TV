import 'package:flutter/material.dart';

import '../core/library.dart';
import '../core/services.dart';
import '../innertube/innertube.dart';
import '../ui/actions.dart';
import '../ui/cards.dart';
import '../ui/focusable.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';

/// A channel: banner, avatar, Subscribe, then tabs (Home as rows; Videos, Live and Playlists as grids).
class ChannelScreen extends StatefulWidget {
  const ChannelScreen({super.key, required this.channel});

  final ChannelItem channel;

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  static const _tabs = ['Home', 'Videos', 'Live', 'Playlists', 'Podcasts'];

  ChannelPage? _page;
  Object? _error;
  bool _loading = true;
  List<YtItem> _items = const [];
  String? _token;
  bool _loadingMore = false;
  final _tabFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load(null);
  }

  @override
  void dispose() {
    _tabFocus.dispose();
    super.dispose();
  }

  Future<void> _load(String? params) async {
    setState(() => _loading = true);
    try {
      final page = await Services.yt.channel(widget.channel.id, params: params);
      if (!mounted) return;
      setState(() {
        _page = page;
        _error = null;
        _items = page.content.entries.allItems.where((i) => i is! VideoItem || !i.isShort).toList();
        _token = page.content.continuation;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _more() async {
    final t = _token;
    if (t == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final p = await Services.yt.browseContinuation(t);
      if (!mounted) return;
      final seen = _items.map((i) => i.id).toSet();
      setState(() {
        _token = p.continuation;
        _items = [..._items, ...p.entries.allItems.where((i) => (i is! VideoItem || !i.isShort) && seen.add(i.id))];
      });
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _sort(SortChip chip) async {
    final t = chip.token;
    if (t == null || chip.selected) return;
    final p = await Services.yt.browseContinuation(t);
    if (!mounted) return;
    setState(() {
      _items = p.entries.allItems.where((i) => i is! VideoItem || !i.isShort).toList();
      _token = p.continuation;
      _page = ChannelPage(
        id: _page!.id,
        name: _page!.name,
        avatar: _page!.avatar,
        banner: _page!.banner,
        handle: _page!.handle,
        metadata: _page!.metadata,
        tabs: _page!.tabs,
        sortChips: [for (final c in _page!.sortChips) SortChip(c.label, c.token, selected: c == chip)],
        content: _page!.content,
      );
    });
  }

  Widget _header(ChannelPage? page) {
    final c = widget.channel;
    final channel = ChannelItem(
      id: c.id,
      name: page?.name ?? c.name,
      avatar: page?.avatar ?? c.avatar,
      subscribersText: page?.metadata.firstOrNull,
    );
    final subscribed = Library.instance.isSubscribed(c.id);
    return SizedBox(
      height: 400,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (page?.banner != null) NetImage(page!.banner, width: 1920),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Tv.bg, Color(0x990F0F0F), Color(0x400F0F0F)],
                stops: [0.08, 0.55, 1],
              ),
            ),
          ),
          Positioned(
            left: Tv.pad,
            right: Tv.pad,
            bottom: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipOval(child: NetImage(channel.avatar, width: 176, height: 176)),
                const SizedBox(width: 40),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        [?page?.handle, ...?page?.metadata].join(' • '),
                        style: const TextStyle(fontSize: 24, color: Color(0xFFCCCCCC)),
                      ),
                      const SizedBox(height: 22),
                      if (page != null)
                        TvButton(
                          label: subscribed ? 'Subscribed' : 'Subscribe',
                          primary: true,
                          on: subscribed,
                          onSelect: () => setState(() => toggleSubscription(channel)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final selected = page?.tabs.where((t) => t.selected).firstOrNull?.title ?? 'Home';
    final actions = defaultActions(context);
    return Material(
      color: Tv.bg,
      child: TvKeys(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 600),
          children: [
            _header(page),
            if (page != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Tv.pad, 0, Tv.pad, 32),
                child: Row(
                  children: [
                    for (final t in page.tabs.where((t) => _tabs.contains(t.title)))
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: TvFocusable(
                          autofocus: t.selected && _items.isEmpty,
                          focusNode: t.selected ? _tabFocus : null,
                          scrollAlignment: 0,
                          onSelect: () => t.selected ? null : _load(t.params),
                          builder: (context, focused) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                            decoration: BoxDecoration(
                              color: focused ? Tv.focusBg : (t.selected ? const Color(0x24FFFFFF) : Colors.transparent),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Text(
                              t.title,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w500,
                                color: focused ? Tv.focusFg : (t.selected ? Tv.text : Tv.text2),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: Tv.pad),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Loading…', style: TextStyle(fontSize: 26, color: Tv.text2)),
                    )
                  : _error != null
                  ? Text("Couldn't load this channel: $_error", style: const TextStyle(fontSize: 26))
                  : selected == 'Home'
                  ? _home(page!, actions)
                  : _grid(page!, actions),
            ),
          ],
        ),
      ),
    );
  }

  Widget _home(ChannelPage page, ItemActions actions) {
    final loose = <YtItem>[];
    final shelves = <ShelfEntry>[];
    for (final e in page.content.entries) {
      switch (e) {
        case ItemEntry(:final item):
          if (item is! VideoItem || !item.isShort) loose.add(item);
        case ShelfEntry s:
          if (!s.shorts) shelves.add(s);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loose.isNotEmpty) TvRow(title: 'Featured', items: loose, actions: actions, autofocus: true),
        for (final s in shelves)
          TvRow(title: s.title, items: s.items, actions: actions, autofocus: loose.isEmpty && s == shelves.first),
      ],
    );
  }

  Widget _grid(ChannelPage page, ItemActions actions) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (page.sortChips.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Row(
            children: [
              for (final c in page.sortChips)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: TvButton(label: c.label, on: !c.selected, onSelect: () => _sort(c)),
                ),
            ],
          ),
        ),
      if (_items.isEmpty)
        const Text('Nothing here', style: TextStyle(fontSize: 26, color: Tv.text2))
      else
        TvGrid(items: _items, actions: actions, onNearEnd: _more),
    ],
  );
}

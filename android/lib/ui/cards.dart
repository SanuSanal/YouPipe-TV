import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/library.dart';
import '../innertube/innertube.dart';
import 'focusable.dart';
import 'theme.dart';

/// Thumbnails and avatars: grey while loading, decoded at the size they're shown.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.width, this.height, this.fit = BoxFit.cover});

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return Container(width: width, height: height, color: Tv.surface2);
    return Image.network(
      u,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: width == null ? null : (width! * 1.2).round(),
      frameBuilder: (context, child, frame, sync) =>
          frame == null && !sync ? Container(width: width, height: height, color: Tv.surface2) : child,
      errorBuilder: (context, e, st) => Container(width: width, height: height, color: Tv.surface2),
    );
  }
}

/// Progress of a video in the watch history, cached until the history changes.
class _Progress {
  static Map<String, double>? _cache;
  static bool _listening = false;

  static double of(String id) {
    if (!_listening) {
      _listening = true;
      Library.instance.addListener(() => _cache = null);
    }
    _cache ??= {for (final h in Library.instance.history()) h.video.id: h.progress};
    return _cache![id] ?? 0;
  }
}

/// A card: video (16:9 thumbnail, title, channel, views and age), channel (round avatar) or playlist.
class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, required this.focused, this.width = Tv.cardWidth});

  final YtItem item;
  final bool focused;
  final double width;

  @override
  Widget build(BuildContext context) => switch (item) {
    VideoItem v => _video(v),
    ChannelItem c => _channel(c),
    PlaylistItem p => _playlist(p),
  };

  bool get _small => width < 420;
  TextStyle get _titleStyle => _small ? Tv.smallCardTitle : Tv.cardTitle;
  TextStyle get _metaStyle => _small ? Tv.smallCardMeta : Tv.cardMeta;

  Widget _thumb(Widget child) => AnimatedScale(
    scale: focused ? 1.06 : 1,
    duration: const Duration(milliseconds: 180),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: focused
            ? const [
                BoxShadow(color: Colors.white, spreadRadius: 5),
                BoxShadow(color: Color(0x99000000), blurRadius: 32, offset: Offset(0, 12)),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(aspectRatio: 16 / 9, child: child),
      ),
    ),
  );

  Widget _video(VideoItem v) {
    final progress = _Progress.of(v.id);
    final meta = [v.viewsText, v.publishedText].whereType<String>().where((s) => s.isNotEmpty).join(' • ');
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _thumb(
            Stack(
              fit: StackFit.expand,
              children: [
                NetImage(v.thumbnailOrDefault, width: width, fit: v.isShort ? BoxFit.contain : BoxFit.cover),
                if (v.isLive || v.durationText != null)
                  Positioned(
                    right: 10,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: v.isLive ? const Color(0xFFCC0000) : const Color(0xD1000000),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        v.isLive ? 'LIVE' : v.durationText!,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Colors.white),
                      ),
                    ),
                  ),
                if (progress > 0.02)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 6,
                    child: Container(
                      color: const Color(0x59FFFFFF),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress.clamp(0, 1),
                        child: Container(color: Tv.brand),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: _titleStyle),
          const SizedBox(height: 4),
          Text(v.channelName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: _metaStyle),
          if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: _metaStyle),
        ],
      ),
    );
  }

  Widget _channel(ChannelItem c) => SizedBox(
    width: width,
    child: Column(
      children: [
        AnimatedScale(
          scale: focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 180),
          child: Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: focused ? const [BoxShadow(color: Colors.white, spreadRadius: 5)] : null,
            ),
            child: ClipOval(child: NetImage(c.avatar, width: 168, height: 168)),
          ),
        ),
        const SizedBox(height: 16),
        Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Tv.cardTitle),
        if (c.subscribersText?.isNotEmpty ?? false)
          Text(
            c.subscribersText!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Tv.cardMeta,
          ),
      ],
    ),
  );

  Widget _playlist(PlaylistItem p) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _thumb(
          Stack(
            fit: StackFit.expand,
            children: [
              NetImage(p.thumbnail, width: width),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: width * 0.4,
                child: Container(
                  color: const Color(0xC7000000),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.playlist_play, size: 40, color: Colors.white),
                      Text(
                        p.countText ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: _titleStyle),
        Text(p.channelName ?? 'Playlist', maxLines: 1, overflow: TextOverflow.ellipsis, style: _metaStyle),
      ],
    ),
  );
}

/// Grey cards while a row loads.
class PlaceholderCard extends StatelessWidget {
  const PlaceholderCard({super.key, this.width = Tv.cardWidth});

  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(color: Tv.surface2),
          ),
        ),
        const SizedBox(height: 22),
        Container(
          height: 22,
          width: width * 0.9,
          decoration: BoxDecoration(color: Tv.surface2, borderRadius: BorderRadius.circular(6)),
        ),
        const SizedBox(height: 14),
        Container(
          height: 22,
          width: width * 0.55,
          decoration: BoxDecoration(color: Tv.surface2, borderRadius: BorderRadius.circular(6)),
        ),
      ],
    ),
  );
}

/// What a row or grid does with its items.
class ItemActions {
  const ItemActions({required this.onSelect, this.onLongPress});

  final void Function(YtItem item) onSelect;
  final void Function(YtItem item)? onLongPress;
}

/// A titled row that slides sideways, like YouTube on TV. One stop for Up/Down; Left/Right move inside it and it
/// remembers its card, so coming back returns there. The focused card stays at the left.
class TvRow extends StatefulWidget {
  const TvRow({
    super.key,
    required this.title,
    required this.items,
    required this.actions,
    this.loading = false,
    this.onNearEnd,
    this.cardWidth = Tv.cardWidth,
    this.focusNode,
    this.autofocus = false,
  });

  final String title;
  final List<YtItem> items;
  final ItemActions actions;
  final bool loading;
  final VoidCallback? onNearEnd;
  final double cardWidth;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<TvRow> createState() => _TvRowState();
}

class _TvRowState extends State<TvRow> {
  final _scroll = ScrollController();
  late final _select = SelectHandler(_activate, _options);
  int _index = 0;
  bool _focused = false;

  double get _extent => widget.cardWidth + Tv.gap;

  bool get _hasChannels => widget.items.isNotEmpty && widget.items.every((i) => i is ChannelItem);

  void _activate() {
    if (_index < widget.items.length) widget.actions.onSelect(widget.items[_index]);
  }

  void _options() {
    final f = widget.actions.onLongPress;
    if (f != null && _index < widget.items.length) f(widget.items[_index]);
  }

  void _moveTo(int i) {
    setState(() => _index = i);
    if (_scroll.hasClients) {
      _scroll.animateTo(
        (i * _extent).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: Tv.slide,
        curve: Curves.easeOut,
      );
    }
    if (i >= widget.items.length - 8) widget.onNearEnd?.call();
  }

  @override
  void didUpdateWidget(TvRow old) {
    super.didUpdateWidget(old);
    if (_index >= widget.items.length) _index = widget.items.isEmpty ? 0 : widget.items.length - 1;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _select.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = _hasChannels ? 260.0 : widget.cardWidth * 9 / 16 + 190;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.items.isNotEmpty,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) revealRow(context);
      },
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent || e is KeyRepeatEvent) {
          if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (_index + 1 < widget.items.length) {
              _moveTo(_index + 1);
              return KeyEventResult.handled;
            }
            return KeyEventResult.handled; // the end of the row: stay
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft && _index > 0) {
            _moveTo(_index - 1);
            return KeyEventResult.handled;
          }
        }
        return _select.handle(e);
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tv.rowTitle),
            const SizedBox(height: 14),
            SizedBox(
              height: height,
              child: ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                clipBehavior: Clip.none,
                padding: const EdgeInsets.only(top: 14, right: Tv.pad),
                itemExtent: _extent,
                itemCount: widget.loading && widget.items.isEmpty ? 5 : widget.items.length,
                itemBuilder: (context, i) => Align(
                  alignment: Alignment.topLeft,
                  child: widget.items.isEmpty
                      ? PlaceholderCard(width: widget.cardWidth)
                      : GestureDetector(
                          onTap: () {
                            _moveTo(i);
                            _activate();
                          },
                          child: ItemCard(
                            item: widget.items[i],
                            focused: _focused && i == _index,
                            width: _hasChannels ? 200 : widget.cardWidth,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A grid of cards, [columns] across. One stop for the remote: the arrows move inside it, and leave it at its edges.
class TvGrid extends StatefulWidget {
  const TvGrid({
    super.key,
    required this.items,
    required this.actions,
    this.columns = 3,
    this.cardWidth = Tv.gridCardWidth,
    this.onNearEnd,
    this.focusNode,
    this.autofocus = false,
    this.onReveal,
    this.holdSides = false,
  });

  final List<YtItem> items;
  final ItemActions actions;
  final int columns;
  final double cardWidth;
  final VoidCallback? onNearEnd;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Brings the focused card (its context) into view; by default its page scrolls to it.
  final void Function(BuildContext card)? onReveal;

  /// Left and Right stop at the grid's sides instead of leaving it (the player's Up next, below its buttons).
  final bool holdSides;

  @override
  State<TvGrid> createState() => _TvGridState();
}

class _TvGridState extends State<TvGrid> {
  final _focusKey = GlobalKey();
  late final _select = SelectHandler(_activate, _options);
  int _index = 0;
  bool _focused = false;

  void _activate() {
    if (_index < widget.items.length) widget.actions.onSelect(widget.items[_index]);
  }

  void _options() {
    final f = widget.actions.onLongPress;
    if (f != null && _index < widget.items.length) f(widget.items[_index]);
  }

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final c = _focusKey.currentContext;
    if (c == null) return;
    final reveal = widget.onReveal;
    if (reveal != null) {
      reveal(c);
    } else {
      Scrollable.ensureVisible(c, alignment: 0.15, duration: Tv.slide, curve: Curves.easeOut);
    }
  });

  KeyEventResult _move(int to) {
    if (to < 0 || to >= widget.items.length) return KeyEventResult.ignored;
    setState(() => _index = to);
    _reveal();
    if (to >= widget.items.length - widget.columns * 2) widget.onNearEnd?.call();
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(TvGrid old) {
    super.didUpdateWidget(old);
    // A new list (the player's Up next for another video) starts from its first card; more of the same list keeps it.
    if (widget.items.firstOrNull?.id != old.items.firstOrNull?.id) _index = 0;
    if (_index >= widget.items.length) _index = widget.items.isEmpty ? 0 : widget.items.length - 1;
  }

  @override
  void dispose() {
    _select.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cols = widget.columns;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.items.isNotEmpty,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) _reveal();
      },
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent || e is KeyRepeatEvent) {
          final k = e.logicalKey;
          final col = _index % cols;
          final side = widget.holdSides ? KeyEventResult.handled : KeyEventResult.ignored;
          if (k == LogicalKeyboardKey.arrowLeft) return col > 0 ? _move(_index - 1) : side;
          if (k == LogicalKeyboardKey.arrowRight) {
            return col < cols - 1 && _index + 1 < widget.items.length ? _move(_index + 1) : side;
          }
          if (k == LogicalKeyboardKey.arrowUp) return _move(_index - cols);
          if (k == LogicalKeyboardKey.arrowDown) {
            if (_index + cols < widget.items.length) return _move(_index + cols);
            // The last row is short: go to its last card.
            final lastRowStart = (widget.items.length - 1) ~/ cols * cols;
            return _index < lastRowStart ? _move(widget.items.length - 1) : KeyEventResult.ignored;
          }
        }
        return _select.handle(e);
      },
      child: Wrap(
        spacing: Tv.gap,
        runSpacing: 44,
        children: [
          for (var i = 0; i < widget.items.length; i++)
            GestureDetector(
              key: i == _index ? _focusKey : ValueKey('${widget.items[i].runtimeType}:${widget.items[i].id}'),
              onTap: () {
                _move(i);
                _activate();
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: ItemCard(item: widget.items[i], focused: _focused && i == _index, width: widget.cardWidth),
              ),
            ),
        ],
      ),
    );
  }
}

/// Scrolls a row into view near the top of its page. The first row under the top bar (shell.dart) brings the page
/// back to its very top instead, so the bar shows again.
void revealRow(BuildContext context) {
  final box = context.findRenderObject();
  final position = Scrollable.maybeOf(context)?.position;
  if (box == null || position == null) return;
  final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
  if (top <= Tv.topbarHeight) {
    position.animateTo(0, duration: Tv.slide, curve: Curves.easeOut);
  } else {
    Scrollable.ensureVisible(context, alignment: 0.05, duration: Tv.slide, curve: Curves.easeOut);
  }
}

/// Runs [tasks] a few at a time, in order.
Future<void> runQueued(List<Future<void> Function()> tasks, {int concurrency = 3}) async {
  var next = 0;
  Future<void> worker() async {
    while (next < tasks.length) {
      final t = tasks[next++];
      try {
        await t();
      } catch (_) {}
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
}

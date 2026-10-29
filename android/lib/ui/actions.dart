import 'package:flutter/material.dart';

import '../core/library.dart';
import '../core/subs_feed.dart';
import '../innertube/innertube.dart';
import '../screens/channel.dart';
import '../screens/playlist.dart';
import '../screens/watch.dart';
import 'cards.dart';
import 'overlay.dart';

/// A full-screen page with a quick fade, like YouTube on TV.
Route<T> tvRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 160),
  reverseTransitionDuration: const Duration(milliseconds: 120),
  pageBuilder: (context, a, b) => page,
  transitionsBuilder: (context, a, b, child) => FadeTransition(opacity: a, child: child),
);

/// Videos to play in order: a playlist (Play all, Shuffle) or the rest of a row.
class PlayQueue {
  PlayQueue(this.items, this.index, {this.title, this.more});

  List<VideoItem> items;
  int index;
  final String? title;
  final Future<List<VideoItem>> Function()? more;
}

/// OK on a card: play a video, open a channel or a playlist.
void openItem(BuildContext context, YtItem item, {PlayQueue? queue}) {
  final nav = Navigator.of(context);
  switch (item) {
    case VideoItem v:
      WatchScreen.open(context, v, queue: queue);
    case ChannelItem c:
      nav.push(tvRoute(ChannelScreen(channel: c)));
    case PlaylistItem p:
      nav.push(tvRoute(PlaylistScreen(playlist: p)));
  }
}

/// Subscribes or unsubscribes, and says so; the feed fetches the channel straight away.
bool toggleSubscription(ChannelItem c) {
  final on = Library.instance.toggleSubscription(c);
  if (on) SubsFeed.refreshChannel(c);
  Toast.show(on ? 'Subscribed to ${c.name}' : 'Unsubscribed from ${c.name}');
  return on;
}

/// Holding OK on a card.
void itemOptions(BuildContext context, YtItem item, {List<PanelItem> extra = const []}) {
  final lib = Library.instance;
  switch (item) {
    case VideoItem v:
      final saved = lib.has('watchLater', v.id);
      showPanel(
        context,
        title: v.title,
        subtitle: v.channelName,
        items: [
          PanelItem('Play', icon: Icons.play_arrow, onSelect: () => openItem(context, v)),
          PanelItem(
            saved ? 'Remove from Watch later' : 'Save to Watch later',
            icon: Icons.watch_later_outlined,
            onSelect: () =>
                Toast.show(lib.toggle('watchLater', v) ? 'Saved to Watch later' : 'Removed from Watch later'),
          ),
          if (v.channelId != null)
            PanelItem(
              'Go to channel',
              sub: v.channelName,
              icon: Icons.account_circle_outlined,
              onSelect: () =>
                  openItem(context, ChannelItem(id: v.channelId!, name: v.channelName ?? '', avatar: v.channelAvatar)),
            ),
          ...extra,
        ],
      );
    case ChannelItem c:
      showPanel(
        context,
        title: c.name,
        items: [
          PanelItem('Open channel', icon: Icons.account_circle_outlined, onSelect: () => openItem(context, c)),
          PanelItem(
            lib.isSubscribed(c.id) ? 'Unsubscribe' : 'Subscribe',
            icon: Icons.notifications_outlined,
            onSelect: () => toggleSubscription(c),
          ),
          ...extra,
        ],
      );
    case PlaylistItem p:
      final saved = lib.has('playlists', p.id);
      showPanel(
        context,
        title: p.title,
        items: [
          PanelItem('Open playlist', icon: Icons.playlist_play, onSelect: () => openItem(context, p)),
          PanelItem(
            saved ? 'Remove from Library' : 'Save to Library',
            icon: Icons.playlist_add,
            onSelect: () => Toast.show(lib.toggle('playlists', p) ? 'Saved to Library' : 'Removed from Library'),
          ),
          ...extra,
        ],
      );
  }
}

/// The usual card actions: OK opens, holding OK shows options.
ItemActions defaultActions(BuildContext context, {List<PanelItem> Function(YtItem)? extra}) => ItemActions(
  onSelect: (i) => openItem(context, i),
  onLongPress: (i) => itemOptions(context, i, extra: extra?.call(i) ?? const []),
);

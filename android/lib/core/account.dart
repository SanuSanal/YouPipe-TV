import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../innertube/auth.dart';
import '../innertube/innertube.dart';
import 'library.dart';
import 'services.dart';
import 'subs_feed.dart';

/// The optional Google account (docs/account.md), signed in the way YouPipe does on phones: Google's own sign-in page
/// (SignInActivity), then InnerTube requests carry the youtube.com session cookie. The cookie stays in encrypted
/// storage on the TV; everything works signed out.
class Account extends ChangeNotifier {
  Account._();

  static final instance = Account._();

  static const _storage = FlutterSecureStorage();
  static const _channel = MethodChannel('youpipe/account');
  static const _cookieKey = 'yt_cookie';

  /// The signed-in account's name and photo; null until loaded (or when offline).
  AccountInfo? info;

  /// True while [import] runs.
  bool importing = false;

  bool get signedIn => Services.yt.signedIn;

  Future<void> init() async {
    try {
      Services.yt.cookie = await _storage.read(key: _cookieKey);
    } catch (e) {
      debugPrint('YouPipe: stored sign-in unreadable: $e');
    }
    Library.instance.remoteSync = _sync;
    if (signedIn) unawaited(_loadInfo());
  }

  Future<void> _loadInfo() async {
    try {
      info = await Services.yt.accountInfo();
      notifyListeners();
    } catch (e) {
      debugPrint('YouPipe: account info failed: $e');
    }
  }

  /// Opens Google's sign-in page; true once signed in, false when the user backed out.
  Future<bool> signIn() async {
    final cookie = await _channel.invokeMethod<String>('signIn');
    if (!isSignedInCookie(cookie)) return false;
    await _storage.write(key: _cookieKey, value: cookie);
    Services.yt.cookie = cookie;
    notifyListeners();
    await _loadInfo();
    return true;
  }

  /// Forgets the session on the TV. The library on the TV stays.
  Future<void> signOut() async {
    await _storage.delete(key: _cookieKey);
    Services.yt.cookie = null;
    info = null;
    await _channel.invokeMethod<bool>('clear').catchError((Object e) {
      debugPrint('YouPipe: clearing cookies failed: $e');
      return false;
    });
    notifyListeners();
  }

  /// Likes, Watch later and subscriptions also go to the account. Best effort: the TV's library stays the source.
  void _sync(String key, String id, bool on) {
    if (!signedIn) return;
    final call = switch (key) {
      'liked' => Services.yt.like(id, liked: on),
      'watchLater' => Services.yt.editPlaylist('WL', id, add: on),
      'subs' => Services.yt.subscribe(id, subscribe: on),
      _ => null,
    };
    call?.catchError((Object e) => debugPrint('YouPipe: account sync $key failed: $e'));
  }

  /// Copies the account's subscriptions and YouTube history into the TV's library, so Home and Subscriptions build on
  /// them. Returns how many channels and videos were new.
  Future<(int, int)> import() async {
    importing = true;
    notifyListeners();
    try {
      final yt = Services.yt;
      var page = await yt.subscribedChannels();
      final channels = [...page.entries.allItems.whereType<ChannelItem>()];
      while (page.continuation != null && channels.length < 2000) {
        page = await yt.browseContinuation(page.continuation!);
        final more = page.entries.allItems.whereType<ChannelItem>().toList();
        if (more.isEmpty) break;
        channels.addAll(more);
      }
      final subs = Library.instance.importSubscriptions(channels);
      if (subs > 0) unawaited(SubsFeed.refresh(force: true));

      var history = await yt.accountFeed('FEhistory');
      final videos = [...history.entries.allItems.whereType<VideoItem>()];
      while (history.continuation != null && videos.length < 300) {
        history = await yt.browseContinuation(history.continuation!);
        final more = history.entries.allItems.whereType<VideoItem>().toList();
        if (more.isEmpty) break;
        videos.addAll(more);
      }
      return (subs, Library.instance.importHistory(videos.where((v) => !v.isLive).toList()));
    } finally {
      importing = false;
      notifyListeners();
    }
  }
}

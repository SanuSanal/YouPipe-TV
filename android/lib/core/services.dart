import 'package:flutter/foundation.dart';

import '../innertube/innertube.dart';
import '../player/player_service.dart';
import '../player/video_info.dart';
import 'account.dart';
import 'library.dart';
import 'settings.dart';
import 'store.dart';

/// The app's single instances, set up once in main.dart.
abstract final class Services {
  /// Browse, search, the watch page's related videos and comments (pure Dart, like YouPipe).
  static final yt = InnerTube();

  /// Streams, captions, storyboards and chapters from NewPipeExtractor (docs/streaming.md).
  static final infos = VideoInfoService();

  static late final PlayerService player;

  static Future<void> init() async {
    await Store.init();
    Settings.init();
    yt.visitorData = Store.instance.get<String>('visitorData');
    applyLocale();
    Settings.instance.addListener(applyLocale);
    player = PlayerService(infos);
    // Library loads lazily from the store.
    Library.instance;
    await Account.instance.init();
    try {
      final v = await yt.ensureVisitorData();
      if (v != null) await Store.instance.set('visitorData', v);
    } catch (e) {
      debugPrint('YouPipe: visitor_id failed: $e');
    }
  }

  static void applyLocale() {
    final s = Settings.instance;
    yt.hl = s.hl;
    yt.gl = s.gl;
    infos.hl = s.hl;
    infos.gl = s.gl;
  }
}

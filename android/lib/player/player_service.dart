import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'playback_proxy.dart';
import 'video_info.dart';

/// How the current video is being played.
enum VideoSource { dash, muxed, hls }

/// The one video player (docs/streaming.md): ExoPlayer through `video_player`, fed a local DASH manifest (up to
/// 1080p), YouTube's muxed 360p stream through the loopback relay, or a live HLS playlist. Adapted from YouPipe's
/// VideoPlayerService, without the phone's background playback, downloads and casting.
class PlayerService {
  PlayerService(this.infos);

  final VideoInfoService infos;

  final controller = ValueNotifier<VideoPlayerController?>(null);
  final info = ValueNotifier<VideoInfo?>(null);
  final error = ValueNotifier<Object?>(null);
  VideoSource? source;

  int _loads = 0;

  /// ExoPlayer can stall forever on a bad stream; give up and fall back instead.
  static const _initTimeout = Duration(seconds: 20);
  static const _system = MethodChannel('youpipe/system');
  bool _awake = false;

  /// While a video plays the screen stays on.
  void _keepAwake(bool on) {
    if (on == _awake) return;
    _awake = on;
    _system
        .invokeMethod<void>('playing', {'playing': on})
        .catchError((Object e) => debugPrint('YouPipe: keep awake: $e'));
  }

  /// Loads [id] and starts it at [start]. Returns false when a newer [open] took over or loading failed ([error]).
  Future<bool> open(
    String id, {
    int maxHeight = 1080,
    Duration start = Duration.zero,
    double speed = 1,
    bool recovering = false,
  }) async {
    final load = ++_loads;
    error.value = null;
    if (!recovering) info.value = null;
    await _release();
    try {
      final i = await infos
          .get(id, maxHeight: maxHeight, forceRefresh: recovering)
          .timeout(const Duration(seconds: 45));
      if (load != _loads) return false;
      info.value = i;
      final (c, s) = await _openController(i);
      if (load != _loads) {
        await c.dispose();
        return false;
      }
      source = s;
      controller.value = c;
      var failed = false;
      var last = start;
      c.addListener(() {
        if (load != _loads) return;
        final v = c.value;
        _keepAwake(v.isPlaying && !v.isCompleted && !v.hasError);
        if (!v.hasError && v.position > Duration.zero) last = v.position;
        // A stream that fails mid-play (an expired URL, a stall) gets fresh URLs once.
        if (v.hasError && !failed) {
          failed = true;
          debugPrint('YouPipe: $id errored at ${last.inSeconds}s (${v.errorDescription})');
          if (!recovering) {
            unawaited(open(id, maxHeight: maxHeight, start: last, speed: speed, recovering: true));
          } else {
            error.value = VideoUnavailable('PLAYBACK_FAILED', v.errorDescription ?? 'Playback failed');
          }
        }
      });
      if (speed != 1) await c.setPlaybackSpeed(speed);
      if (start > Duration.zero) await c.seekTo(start);
      await c.play();
      return true;
    } catch (e) {
      if (load == _loads) error.value = e;
      debugPrint('YouPipe: open $id failed: $e');
      return false;
    }
  }

  /// Live → HLS; otherwise the HD manifest, falling back to the muxed stream if ExoPlayer rejects it.
  Future<(VideoPlayerController, VideoSource)> _openController(VideoInfo i) async {
    if (i.isLive && i.hlsUrl != null) {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(i.hlsUrl!),
        formatHint: VideoFormat.hls,
        httpHeaders: {'User-Agent': i.hlsUserAgent},
      );
      await c.initialize().timeout(_initTimeout);
      return (c, VideoSource.hls);
    }
    if (i.manifestPath != null) {
      // A file URI still goes through the plugin's HTTP data source, so the manifest's googlevideo requests carry
      // the User-Agent (docs/streaming.md).
      final c = VideoPlayerController.networkUrl(
        Uri.file(i.manifestPath!),
        formatHint: VideoFormat.dash,
        httpHeaders: {'User-Agent': i.dashUserAgent},
      );
      try {
        await c.initialize().timeout(_initTimeout);
        return (c, VideoSource.dash);
      } catch (e) {
        debugPrint('YouPipe: DASH failed for ${i.videoId}, using muxed: $e');
        unawaited(c.dispose());
      }
    }
    final url = i.muxedUrl;
    if (url == null) throw VideoUnavailable('NO_STREAMS', 'Nothing playable for ${i.videoId}');
    // The progressive stream goes through the loopback relay, which fetches it in 1 MB ranges at full speed.
    final relayed = await PlaybackProxy.uriFor(url);
    final c = VideoPlayerController.networkUrl(
      relayed ?? Uri.parse(url),
      httpHeaders: {'User-Agent': i.muxedUserAgent},
    );
    await c.initialize().timeout(_initTimeout);
    return (c, VideoSource.muxed);
  }

  Future<void> _release() async {
    final c = controller.value;
    controller.value = null;
    source = null;
    await c?.dispose();
  }

  Future<void> stop() async {
    _loads++;
    info.value = null;
    error.value = null;
    _keepAwake(false);
    await _release();
  }
}

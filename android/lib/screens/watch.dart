import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/extras.dart';
import '../core/format.dart';
import '../core/library.dart';
import '../core/services.dart';
import '../core/settings.dart';
import '../innertube/innertube.dart';
import '../player/captions.dart';
import '../player/video_info.dart';
import '../ui/actions.dart';
import '../ui/cards.dart';
import '../ui/focusable.dart';
import '../ui/overlay.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';

/// The player screen, like YouTube on TV (docs/ui.md):
/// - The video fills the screen. OK, Up or Down shows the controls; Left/Right seek straight away with a preview.
/// - Controls: title and channel at the top; the seek bar (storyboard preview, chapters, SponsorBlock segments); a
///   row of buttons; and below it Up next (the queue, or related videos) as a grid, 3 across.
/// - Back hides the controls, then leaves the player.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.video, this.queue});

  final VideoItem video;
  final PlayQueue? queue;

  static _WatchScreenState? _current;

  /// Plays [video]; when the player is already open, it plays there.
  static void open(BuildContext context, VideoItem video, {PlayQueue? queue}) {
    final current = _current;
    if (current != null && current.mounted) {
      Navigator.of(context).popUntil((r) => r.settings.name == 'watch' || r.isFirst);
      current._play(video, queue: queue);
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: 'watch'),
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (context, a, b) => WatchScreen(video: video, queue: queue),
        transitionsBuilder: (context, a, b, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  static const _hideAfter = Duration(seconds: 5);
  final _player = Services.player;
  final _root = FocusNode(debugLabel: 'watch');
  final _bar = FocusNode(debugLabel: 'seekbar');
  final _playButton = FocusNode(debugLabel: 'play');
  final _upNext = FocusNode(debugLabel: 'upnext');

  late VideoItem _item;
  PlayQueue? _queue;
  List<YtItem> _related = const [];
  List<SbSegment> _segments = const [];
  final _skipped = <SbSegment>{};
  int? _dislikes;
  List<Cue>? _cues;
  CaptionTrack? _track;
  String _caption = '';

  bool _controls = true;
  bool _upNextFocused = false;
  final _column = GlobalKey();
  double _slide = 0;
  Duration? _scrubTo;
  int _scrubCount = 0;
  DateTime _lastScrub = DateTime(0);
  Timer? _hideTimer;
  Timer? _scrubTimer;
  Timer? _saveTimer;
  Timer? _countdownTimer;
  int? _countdown;
  VideoPlayerController? _listening;
  bool _completedHandled = false;

  @override
  void initState() {
    super.initState();
    WatchScreen._current = this;
    _player.controller.addListener(_onController);
    _player.info.addListener(_rebuild);
    _player.error.addListener(_onError);
    _upNext.addListener(() => setState(() => _upNextFocused = _upNext.hasFocus));
    _play(widget.video, queue: widget.queue);
  }

  @override
  void dispose() {
    if (WatchScreen._current == this) WatchScreen._current = null;
    _saveProgress();
    _hideTimer?.cancel();
    _scrubTimer?.cancel();
    _saveTimer?.cancel();
    _countdownTimer?.cancel();
    _listening?.removeListener(_onTick);
    _player.controller.removeListener(_onController);
    _player.info.removeListener(_rebuild);
    _player.error.removeListener(_onError);
    _player.stop();
    for (final n in [_root, _bar, _playButton, _upNext]) {
      n.dispose();
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  VideoPlayerController? get _c => _player.controller.value;
  VideoInfo? get _info => _player.info.value;

  // Loading ------------------------------------------------------------------------------------------------------

  Future<void> _play(VideoItem video, {PlayQueue? queue}) async {
    _saveProgress();
    _countdownTimer?.cancel();
    setState(() {
      _item = video;
      _queue = queue;
      _related = const [];
      _segments = const [];
      _skipped.clear();
      _dislikes = null;
      _cues = null;
      _track = null;
      _caption = '';
      _countdown = null;
      _scrubTo = null;
      _completedHandled = false;
      // Up next leaves with its old cards; the controls drop back down for the new video.
      _upNextFocused = false;
      _slide = 0;
    });
    _showControls(focusPlay: true);
    Services.yt.related(video.id).then((p) {
      if (mounted && _item.id == video.id) {
        setState(() => _related = p.items.where((i) => i is! VideoItem || (!i.isShort && i.id != video.id)).toList());
      }
    }, onError: (Object e) => debugPrint('YouPipe: related failed: $e'));
    final h = Library.instance.progress(video.id);
    final resume = h != null && h.duration > 0 && h.position > 10 && h.position < h.duration - 30
        ? Duration(seconds: h.position)
        : Duration.zero;
    final ok = await _player.open(
      video.id,
      maxHeight: Settings.instance.maxHeight,
      start: resume,
      speed: Settings.instance.speed,
    );
    if (!ok || !mounted || _item.id != video.id) return;
    if (resume > Duration.zero) Toast.show('Resuming from ${formatDuration(resume)}');
    final info = _info;
    if (info != null) {
      _item = VideoItem(
        id: video.id,
        title: info.title.isNotEmpty ? info.title : video.title,
        channelName: info.channelName.isNotEmpty ? info.channelName : video.channelName,
        channelId: info.channelId ?? video.channelId,
        channelAvatar: info.channelAvatar ?? video.channelAvatar,
        thumbnail: video.thumbnail,
        durationText: video.durationText,
        viewsText: video.viewsText,
        publishedText: video.publishedText,
        isLive: info.isLive,
      );
      if (Settings.instance['captions'] == true) {
        final lang = Settings.instance.captionLang;
        final same = info.captions.where((t) => t.languageCode.split('-').first == lang).toList();
        final track =
            same.where((t) => !t.autoGenerated).firstOrNull ??
            same.firstOrNull ??
            info.captions.where((t) => !t.autoGenerated).firstOrNull;
        if (track != null) unawaited(_setCaptions(track));
      }
    }
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
    SponsorBlock.segments(video.id).then((s) {
      if (mounted && _item.id == video.id) setState(() => _segments = s);
    });
    Dislikes.count(video.id).then((n) {
      if (mounted && _item.id == video.id) setState(() => _dislikes = n);
    });
  }

  void _onController() {
    _listening?.removeListener(_onTick);
    _listening = _c;
    _listening?.addListener(_onTick);
    _rebuild();
  }

  void _onError() {
    if (_player.error.value != null) _showControls(focusPlay: true);
    _rebuild();
  }

  void _saveProgress() {
    final c = _c;
    final info = _info;
    if (c == null || info == null || info.isLive || !c.value.isInitialized) return;
    final pos = c.value.position.inSeconds;
    if (pos < 3) return;
    Library.instance.saveProgress(_item, pos, c.value.duration.inSeconds);
  }

  // Playback events ----------------------------------------------------------------------------------------------

  void _onTick() {
    final c = _c;
    if (c == null || !mounted) return;
    final v = c.value;
    // SponsorBlock: skip each "skip" segment once.
    for (final s in _segments) {
      if (s.category.currentAction == 'skip' &&
          !_skipped.contains(s) &&
          v.position >= s.start &&
          v.position < s.end - const Duration(milliseconds: 500)) {
        _skipped.add(s);
        c.seekTo(s.end);
        Toast.show('Skipped ${s.category.label.toLowerCase()}');
        break;
      }
    }
    final cues = _cues;
    final caption = cues == null ? '' : Captions.at(cues, v.position);
    if (v.isCompleted && !_completedHandled) {
      _completedHandled = true;
      _onEnded();
    }
    if (caption != _caption || _controls) setState(() => _caption = caption);
  }

  void _onEnded() {
    _saveProgress();
    final next = _nextItem();
    if (next == null) return _showControls(focusPlay: true);
    if (_queue != null) {
      unawaited(_goNext());
      return;
    }
    if (!Settings.instance.autoplay) return _showControls(focusPlay: true);
    // YouTube's countdown before the next video.
    setState(() {
      _countdown = 5;
      _controls = false;
    });
    _root.requestFocus();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _countdown = _countdown! - 1);
      if (_countdown! <= 0) {
        t.cancel();
        _goNext();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = null);
    _showControls(focusPlay: true);
  }

  // Queue ----------------------------------------------------------------------------------------------------------

  VideoItem? _nextItem() {
    final q = _queue;
    if (q != null) return q.index < q.items.length - 1 ? q.items[q.index + 1] : null;
    final watched = {for (final h in Library.instance.history().take(50)) h.video.id};
    final related = _related.whereType<VideoItem>();
    return related.where((v) => !watched.contains(v.id)).firstOrNull ?? related.firstOrNull;
  }

  Future<void> _goNext() async {
    final q = _queue;
    if (q != null && q.index >= q.items.length - 1 && q.more != null) {
      final more = await q.more!();
      q.items = [...q.items, ...more.where((m) => !q.items.any((i) => i.id == m.id))];
    }
    if (q != null && q.index < q.items.length - 1) {
      q.index++;
      return _play(q.items[q.index], queue: q);
    }
    final next = _nextItem();
    if (next != null) await _play(next);
  }

  void _goPrevious() {
    final c = _c;
    final q = _queue;
    if (c == null) return;
    if (c.value.position > const Duration(seconds: 5) || q == null || q.index == 0) {
      c.seekTo(Duration.zero);
      return;
    }
    q.index--;
    _play(q.items[q.index], queue: q);
  }

  // Controls ---------------------------------------------------------------------------------------------------------

  void _showControls({bool focusPlay = false, bool focusBar = false}) {
    if (!mounted) return;
    final wasHidden = !_controls;
    setState(() => _controls = true);
    if (focusBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bar.requestFocus());
    } else if (focusPlay || wasHidden) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playButton.requestFocus());
    }
    _scheduleHide();
  }

  void _hideControls() {
    if (_scrubTo != null || _player.error.value != null) return;
    setState(() => _controls = false);
    _root.requestFocus();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      final c = _c;
      if (mounted && c != null && c.value.isPlaying && ModalRoute.of(context)?.isCurrent == true) _hideControls();
    });
  }

  void _togglePause() {
    final c = _c;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
    _showControls();
  }

  // Seeking ----------------------------------------------------------------------------------------------------------

  /// Moves the pending seek position; it's applied when the keys stop (or on OK).
  void _scrub(int dir) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (_info?.isLive ?? false) {
      c.seekTo(c.value.position + Duration(seconds: 10 * dir));
      return;
    }
    final now = DateTime.now();
    _scrubCount = now.difference(_lastScrub) < const Duration(milliseconds: 500) ? _scrubCount + 1 : 0;
    _lastScrub = now;
    final step = Duration(seconds: _scrubCount > 20 ? 60 : (_scrubCount > 8 ? 30 : 10));
    final from = _scrubTo ?? c.value.position;
    final d = c.value.duration;
    var to = dir > 0 ? from + step : from - step;
    if (to < Duration.zero) to = Duration.zero;
    if (to > d - const Duration(seconds: 1)) to = d - const Duration(seconds: 1);
    setState(() => _scrubTo = to);
    _scrubTimer?.cancel();
    _scrubTimer = Timer(const Duration(milliseconds: 800), _commitScrub);
    _scheduleHide();
  }

  void _commitScrub() {
    final to = _scrubTo;
    _scrubTimer?.cancel();
    if (to == null) return;
    _c?.seekTo(to);
    setState(() => _scrubTo = null);
    _scheduleHide();
  }

  // Keys -------------------------------------------------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    // OK's release after showing the controls doesn't press the button it lands on (SelectHandler needs the press).
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (_countdown != null) {
      if (isSelectKey(k)) {
        _countdownTimer?.cancel();
        setState(() => _countdown = null);
        _goNext();
      } else {
        _cancelCountdown();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.space) {
      _togglePause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlay) {
      _c?.play();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPause) {
      _c?.pause();
      _showControls();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaStop) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackNext || k == LogicalKeyboardKey.channelUp) {
      _goNext();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackPrevious || k == LogicalKeyboardKey.channelDown) {
      _goPrevious();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward || k == LogicalKeyboardKey.mediaRewind) {
      if (!_controls) _showControls(focusBar: true);
      _scrub(k == LogicalKeyboardKey.mediaFastForward ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (!_controls) {
      if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
        _showControls(focusBar: true);
        _scrub(k == LogicalKeyboardKey.arrowRight ? 1 : -1);
        return KeyEventResult.handled;
      }
      if (isSelectKey(k) || k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
        _showControls(focusPlay: true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    _scheduleHide();
    if (k == LogicalKeyboardKey.arrowUp && _bar.hasFocus) {
      _hideControls();
      return KeyEventResult.handled;
    }
    // Everything else moves focus between the controls.
    final dir = TvKeys.direction(k);
    if (dir != null) {
      FocusManager.instance.primaryFocus?.focusInDirection(dir);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _onBack() {
    if (_scrubTo != null) {
      setState(() => _scrubTo = null);
      return true;
    }
    if (_countdown != null) {
      _cancelCountdown();
      return true;
    }
    final c = _c;
    if (_controls && _player.error.value == null && c != null && c.value.isPlaying) {
      _hideControls();
      return true;
    }
    return false;
  }

  // Panels -----------------------------------------------------------------------------------------------------------

  Future<void> _setCaptions(CaptionTrack? track) async {
    setState(() {
      _track = track;
      _cues = null;
      _caption = '';
    });
    if (track == null) return;
    try {
      final cues = await Captions.load(track.url);
      if (mounted && _track == track) setState(() => _cues = cues);
    } catch (e) {
      Toast.show("Couldn't load captions");
    }
  }

  void _captionsPanel() {
    final tracks = _info?.captions ?? const <CaptionTrack>[];
    if (tracks.isEmpty) return Toast.show('No captions for this video');
    showPanel(
      context,
      title: 'Captions',
      items: [
        PanelItem('Off', checked: _track == null, onSelect: () => _setCaptions(null)),
        for (final t in tracks) PanelItem(t.name, checked: _track?.url == t.url, onSelect: () => _setCaptions(t)),
      ],
    );
  }

  void _settingsPanel() {
    final c = _c;
    final info = _info;
    if (c == null || info == null) return;
    final speed = c.value.playbackSpeed;
    showPanel(
      context,
      title: 'Settings',
      items: [
        PanelItem(
          'Quality',
          icon: Icons.tune,
          value: info.dashHeights.isEmpty
              ? '${info.muxedHeight ?? ''}p'
              : 'Up to ${Services.player.source == null ? '' : '${info.dashHeights.last}p'}',
          onSelect: () => showPanel(
            context,
            title: 'Quality',
            items: [
              for (final h in info.dashHeights.reversed)
                PanelItem(
                  '${h}p',
                  checked: h == info.dashHeights.last,
                  onSelect: () {
                    final pos = c.value.position;
                    _player.open(_item.id, maxHeight: h, start: pos, speed: speed);
                  },
                ),
            ],
          ),
        ),
        PanelItem(
          'Playback speed',
          icon: Icons.speed,
          value: speed == 1 ? 'Normal' : '$speed×',
          onSelect: () => showPanel(
            context,
            title: 'Playback speed',
            items: [
              for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
                PanelItem(r == 1 ? 'Normal' : '$r×', checked: speed == r, onSelect: () => c.setPlaybackSpeed(r)),
            ],
          ),
        ),
        PanelItem(
          'Captions',
          icon: Icons.closed_caption_outlined,
          value: _track?.name ?? 'Off',
          onSelect: _captionsPanel,
        ),
        PanelItem(
          'Autoplay',
          icon: Icons.playlist_play,
          value: Settings.instance.autoplay ? 'On' : 'Off',
          onSelect: () => Settings.instance.set('autoplay', !Settings.instance.autoplay),
        ),
      ],
    );
  }

  void _infoPanel() {
    final info = _info;
    final chapters = info?.chapters ?? const <Chapter>[];
    final paragraphs = (info?.description ?? '')
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    showPanel(
      context,
      title: _item.title,
      subtitle: [
        if ((info?.viewCount ?? -1) >= 0) viewsLabel(info!.viewCount),
        ?relativeDate(info?.uploadDate),
      ].join(' • '),
      wide: true,
      content: (ctx) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
        children: [
          if (chapters.isNotEmpty) const _PanelHeading('Chapters'),
          for (final (i, ch) in chapters.indexed)
            PanelRow(
              autofocus: i == 0,
              item: PanelItem(ch.title, sub: formatDuration(ch.start)),
              onSelect: () {
                Navigator.of(ctx).pop();
                _c?.seekTo(ch.start);
              },
            ),
          if (chapters.isNotEmpty) const _PanelHeading('Description'),
          for (final (i, p) in (paragraphs.isEmpty ? ['No description'] : paragraphs).indexed)
            TvFocusable(
              autofocus: chapters.isEmpty && i == 0,
              builder: (context, focused) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: focused ? const Color(0x14FFFFFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(p, style: const TextStyle(fontSize: 24, height: 1.5, color: Tv.text)),
              ),
            ),
        ],
      ),
    );
  }

  void _commentsPanel() => showPanel(
    context,
    title: 'Comments',
    wide: true,
    content: (ctx) => _CommentsList(videoId: _item.id),
  );

  // Building ---------------------------------------------------------------------------------------------------------

  Duration get _duration {
    final c = _c;
    if (c != null && c.value.duration > Duration.zero) return c.value.duration;
    return _info?.duration ?? Duration.zero;
  }

  Chapter? _chapterAt(Duration t) {
    Chapter? cur;
    for (final c in _info?.chapters ?? const <Chapter>[]) {
      if (c.start <= t) cur = c;
    }
    return cur;
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final v = c?.value;
    final info = _info;
    final error = _player.error.value;
    final loading = error == null && (c == null || !v!.isInitialized || v.isBuffering);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _onBack()) return;
        Navigator.of(context).pop();
      },
      child: Focus(
        focusNode: _root,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Material(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (c != null && v!.isInitialized)
                Center(
                  child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(c)),
                ),
              // Shade behind the controls.
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _controls ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _upNextFocused ? const Color(0xBF000000) : null,
                      gradient: _upNextFocused
                          ? null
                          : const LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Color(0xEB000000),
                                Color(0x8C000000),
                                Color(0x00000000),
                                Color(0x00000000),
                                Color(0xCC000000),
                              ],
                              stops: [0, 0.38, 0.62, 0.7, 1],
                            ),
                    ),
                  ),
                ),
              ),
              if (_caption.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _controls ? 340 : 96,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1500),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xB8080808), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        _caption,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 42, height: 1.35, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              _top(info),
              _controlsView(c, info),
              if (loading)
                const Center(
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: CircularProgressIndicator(strokeWidth: 8, color: Colors.white),
                  ),
                ),
              if (error != null)
                Positioned(
                  left: 160,
                  right: 160,
                  top: 420,
                  child: Text(
                    "Couldn't play this video. ${error is VideoUnavailable ? error.friendly : error}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 34, height: 1.4),
                  ),
                ),
              if (_countdown != null) _countdownView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _top(VideoInfo? info) => Positioned(
    left: 96,
    right: 96,
    top: 64,
    child: IgnorePointer(
      // It fades out while Up next has focus, as the controls slide up past it.
      child: AnimatedOpacity(
        opacity: _controls && _countdown == null && !_upNextFocused ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1500),
              child: Text(
                _item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (info?.channelAvatar != null) ...[
                  ClipOval(child: NetImage(info!.channelAvatar, width: 52, height: 52)),
                  const SizedBox(width: 16),
                ],
                Text(info?.channelName ?? _item.channelName ?? '', style: const TextStyle(fontSize: 26)),
                if ((info?.subscriberCount ?? -1) >= 0) ...[
                  const SizedBox(width: 16),
                  Text(
                    '${compactCount(info!.subscriberCount)} subscribers',
                    style: const TextStyle(fontSize: 22, color: Tv.text2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              [
                if ((info?.viewCount ?? -1) >= 0)
                  (info!.isLive ? '${compactCount(info.viewCount)} watching' : viewsLabel(info.viewCount)),
                ?relativeDate(info?.uploadDate),
              ].join(' • '),
              style: const TextStyle(fontSize: 22, color: Color(0xFFCCCCCC)),
            ),
          ],
        ),
      ),
    ),
  );

  /// Slides the controls up so the focused Up next card's bottom sits 72 px above the screen's bottom edge.
  void _revealUpNext(BuildContext card) {
    final box = card.findRenderObject() as RenderBox?;
    final column = _column.currentContext?.findRenderObject();
    if (box == null || column == null) return;
    final bottom = 800 + box.localToGlobal(Offset.zero, ancestor: column).dy + box.size.height;
    setState(() => _slide = bottom > 1080 - 72 ? bottom - (1080 - 72) : 0);
  }

  Widget _controlsView(VideoPlayerController? c, VideoInfo? info) {
    final v = c?.value;
    final live = info?.isLive ?? false;
    final d = _duration;
    final pos = _scrubTo ?? v?.position ?? Duration.zero;
    final chapter = _chapterAt(pos);
    final upNext = _queue != null ? _queue!.items.skip(_queue!.index + 1).toList() : _related;
    return Positioned(
      left: 96,
      right: 96,
      top: 800,
      // Focus in Up next slides the controls up until the focused card's row sits above the screen's bottom edge.
      child: AnimatedContainer(
        transform: Matrix4.translationValues(0, _upNextFocused ? -_slide : 0, 0),
        duration: Tv.slide,
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _controls && _countdown == null ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: ExcludeFocus(
            excluding: !_controls,
            child: Column(
              key: _column,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SeekBar(
                  focusNode: _bar,
                  position: v?.position ?? Duration.zero,
                  buffered: (v?.buffered.isNotEmpty ?? false) ? v!.buffered.last.end : Duration.zero,
                  scrubTo: _scrubTo,
                  duration: d,
                  live: live,
                  chapters: info?.chapters ?? const [],
                  segments: _segments,
                  storyboard: info?.storyboards.lastOrNull,
                  chapterAt: _chapterAt,
                  onScrub: _scrub,
                  onSelect: () => _scrubTo != null ? _commitScrub() : _togglePause(),
                ),
                Row(
                  children: [
                    Text(
                      live ? 'LIVE' : formatDuration(pos),
                      style: TextStyle(
                        fontSize: 24,
                        color: live ? const Color(0xFFFF4E45) : const Color(0xFFDDDDDD),
                        fontWeight: live ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        chapter?.title ?? '',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                    if (!live) Text(formatDuration(d), style: const TextStyle(fontSize: 24, color: Color(0xFFDDDDDD))),
                  ],
                ),
                const SizedBox(height: 22),
                _buttons(c, info),
                const SizedBox(height: 56),
                if (upNext.isNotEmpty) ...[
                  Text(
                    _queue != null ? 'Up next in ${_queue!.title ?? 'this playlist'}' : 'Up next',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tv.rowTitle,
                  ),
                  const SizedBox(height: 14),
                  TvGrid(
                    focusNode: _upNext,
                    items: upNext.take(30).toList(),
                    onReveal: _revealUpNext,
                    actions: ItemActions(
                      onSelect: (it) {
                        if (it is! VideoItem) return openItem(context, it);
                        final q = _queue;
                        if (q != null) {
                          q.index = q.items.indexWhere((x) => x.id == it.id);
                          _play(it, queue: q);
                        } else {
                          _play(it);
                        }
                      },
                      onLongPress: (it) => itemOptions(context, it),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buttons(VideoPlayerController? c, VideoInfo? info) {
    final lib = Library.instance;
    final playing = c?.value.isPlaying ?? false;
    final channel = (info?.channelId ?? _item.channelId) == null
        ? null
        : ChannelItem(
            id: info?.channelId ?? _item.channelId!,
            name: info?.channelName ?? _item.channelName ?? '',
            avatar: info?.channelAvatar,
          );
    final liked = lib.has('liked', _item.id);
    final subscribed = channel != null && lib.isSubscribed(channel.id);
    return Row(
      children: [
        _WatchButton(icon: Icons.skip_previous, onSelect: _goPrevious),
        const SizedBox(width: 16),
        _WatchButton(
          icon: playing ? Icons.pause : Icons.play_arrow,
          big: true,
          focusNode: _playButton,
          onSelect: _togglePause,
        ),
        const SizedBox(width: 16),
        _WatchButton(icon: Icons.skip_next, onSelect: _goNext),
        const Spacer(),
        _WatchButton(
          icon: liked ? Icons.thumb_up : Icons.thumb_up_outlined,
          label: (info?.likeCount ?? -1) >= 0 ? compactCount(info!.likeCount) : 'Like',
          on: liked,
          onSelect: () => setState(
            () => Toast.show(lib.toggle('liked', _item) ? 'Added to Liked videos' : 'Removed from Liked videos'),
          ),
        ),
        if (_dislikes != null) ...[
          const SizedBox(width: 16),
          _WatchButton(
            icon: Icons.thumb_down_outlined,
            label: compactCount(_dislikes!),
            onSelect: () => Toast.show('Estimated by Return YouTube Dislike'),
          ),
        ],
        const SizedBox(width: 16),
        _WatchButton(
          icon: Icons.watch_later_outlined,
          label: lib.has('watchLater', _item.id) ? 'Saved' : 'Save',
          onSelect: () => setState(
            () => Toast.show(lib.toggle('watchLater', _item) ? 'Saved to Watch later' : 'Removed from Watch later'),
          ),
        ),
        if (channel != null) ...[
          const SizedBox(width: 16),
          _WatchButton(
            icon: Icons.notifications_outlined,
            label: subscribed ? 'Subscribed' : 'Subscribe',
            on: subscribed,
            onSelect: () => setState(() => toggleSubscription(channel)),
          ),
        ],
        const SizedBox(width: 16),
        _WatchButton(icon: Icons.closed_caption_outlined, on: _track != null, onSelect: _captionsPanel),
        const SizedBox(width: 16),
        _WatchButton(icon: Icons.tune, onSelect: _settingsPanel),
        const SizedBox(width: 16),
        _WatchButton(icon: Icons.info_outline, onSelect: _infoPanel),
        const SizedBox(width: 16),
        _WatchButton(icon: Icons.comment_outlined, onSelect: _commentsPanel),
        if (channel != null) ...[
          const SizedBox(width: 16),
          _WatchButton(icon: Icons.account_circle_outlined, onSelect: () => openItem(context, channel)),
        ],
      ],
    );
  }

  Widget _countdownView() {
    final next = _nextItem();
    return Positioned(
      right: 96,
      bottom: 96,
      width: 600,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: const Color(0xF5212121), borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Up next in ${_countdown ?? 0}', style: const TextStyle(fontSize: 26, color: Tv.text2)),
            const SizedBox(height: 18),
            if (next != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(aspectRatio: 16 / 9, child: NetImage(next.thumbnailOrDefault, width: 536)),
              ),
            const SizedBox(height: 18),
            Text(
              next?.title ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
            ),
            Text(next?.channelName ?? '', style: const TextStyle(fontSize: 22, color: Tv.text2)),
            const SizedBox(height: 18),
            const Text('OK plays it now • Back cancels', style: TextStyle(fontSize: 22, color: Tv.text2)),
          ],
        ),
      ),
    );
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Tv.text2),
    ),
  );
}

/// A round control button; white while focused.
class _WatchButton extends StatelessWidget {
  const _WatchButton({
    required this.icon,
    this.label,
    this.onSelect,
    this.big = false,
    this.on = false,
    this.focusNode,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onSelect;
  final bool big;
  final bool on;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => TvFocusable(
    focusNode: focusNode,
    onSelect: onSelect,
    scrollAlignment: null,
    builder: (context, focused) => AnimatedScale(
      scale: focused ? 1.08 : 1,
      duration: const Duration(milliseconds: 150),
      child: Container(
        height: big ? 88 : 72,
        constraints: BoxConstraints(minWidth: big ? 88 : 72),
        padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 20),
        decoration: BoxDecoration(
          color: focused ? Tv.focusBg : const Color(0x24FFFFFF),
          borderRadius: BorderRadius.circular(44),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: big ? 48 : 34,
              color: focused ? Tv.focusFg : (on ? const Color(0xFF3EA6FF) : Colors.white),
            ),
            if (label != null) ...[
              const SizedBox(width: 12),
              Text(
                label!,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: focused ? Tv.focusFg : Colors.white),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// The seek bar: Left/Right move a pending position (with a storyboard preview and the chapter's name), OK applies.
class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.focusNode,
    required this.position,
    required this.buffered,
    required this.scrubTo,
    required this.duration,
    required this.live,
    required this.chapters,
    required this.segments,
    required this.storyboard,
    required this.chapterAt,
    required this.onScrub,
    required this.onSelect,
  });

  final FocusNode focusNode;
  final Duration position;
  final Duration buffered;
  final Duration? scrubTo;
  final Duration duration;
  final bool live;
  final List<Chapter> chapters;
  final List<SbSegment> segments;
  final Storyboard? storyboard;
  final Chapter? Function(Duration) chapterAt;
  final ValueChanged<int> onScrub;
  final VoidCallback onSelect;

  double _f(Duration t) =>
      duration.inMilliseconds <= 0 ? 0 : (t.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) => TvFocusable(
    focusNode: focusNode,
    scrollAlignment: null,
    onSelect: onSelect,
    onKey: (e) {
      if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
      if (e.logicalKey == LogicalKeyboardKey.arrowLeft || e.logicalKey == LogicalKeyboardKey.arrowRight) {
        onScrub(e.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    builder: (context, focused) => LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final knob = live ? 1.0 : _f(scrubTo ?? position);
        final barHeight = focused ? 10.0 : 6.0;
        return SizedBox(
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: barHeight,
                decoration: BoxDecoration(color: const Color(0x4DFFFFFF), borderRadius: BorderRadius.circular(5)),
              ),
              if (!live) Container(height: barHeight, width: w * _f(buffered), color: const Color(0x73FFFFFF)),
              for (final s in segments)
                Positioned(
                  left: w * _f(s.start),
                  width: w * (_f(s.end) - _f(s.start)),
                  child: Container(height: barHeight, color: s.category.color.withValues(alpha: 0.9)),
                ),
              Container(
                height: barHeight,
                width: live ? w : w * _f(position),
                color: live ? const Color(0xFFCC0000) : Tv.brand,
              ),
              for (final c in chapters)
                if (c.start > Duration.zero)
                  Positioned(
                    left: w * _f(c.start) - 2,
                    child: Container(width: 4, height: barHeight, color: const Color(0xD9000000)),
                  ),
              if (focused)
                Positioned(
                  left: w * knob - 12,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: scrubTo != null ? Colors.white : Tv.brand),
                  ),
                ),
              if (scrubTo != null)
                Positioned(
                  left: (w * knob - 170).clamp(0.0, w - 340),
                  bottom: 48,
                  width: 340,
                  child: Column(
                    children: [
                      if (storyboard != null) _StoryboardFrame(sb: storyboard!, at: scrubTo!),
                      const SizedBox(height: 12),
                      Text(
                        chapterAt(scrubTo!)?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22),
                      ),
                      Text(formatDuration(scrubTo!), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// One frame of a storyboard sprite sheet, 320 wide.
class _StoryboardFrame extends StatelessWidget {
  const _StoryboardFrame({required this.sb, required this.at});

  final Storyboard sb;
  final Duration at;

  @override
  Widget build(BuildContext context) {
    final perFrame = sb.durationPerFrame.inMilliseconds;
    if (perFrame <= 0 || sb.urls.isEmpty) return const SizedBox.shrink();
    final i = (at.inMilliseconds ~/ perFrame).clamp(0, sb.totalCount - 1);
    final perPage = sb.framesPerPageX * sb.framesPerPageY;
    final page = (i ~/ perPage).clamp(0, sb.urls.length - 1);
    final inPage = i % perPage;
    final col = inPage % sb.framesPerPageX;
    final row = inPage ~/ sb.framesPerPageX;
    const w = 320.0;
    final h = w * sb.frameHeight / sb.frameWidth;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.white, spreadRadius: 4)],
      ),
      clipBehavior: Clip.antiAlias,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        maxWidth: w * sb.framesPerPageX,
        maxHeight: h * sb.framesPerPageY,
        child: Transform.translate(
          offset: Offset(-col * w, -row * h),
          child: Image.network(
            sb.urls[page],
            width: w * sb.framesPerPageX,
            height: h * sb.framesPerPageY,
            fit: BoxFit.fill,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

/// The comments panel's list, loading more as focus nears the end.
class _CommentsList extends StatefulWidget {
  const _CommentsList({required this.videoId});

  final String videoId;

  @override
  State<_CommentsList> createState() => _CommentsListState();
}

class _CommentsListState extends State<_CommentsList> {
  final _comments = <CommentData>[];
  String? _token;
  bool _loading = true;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = _token == null
          ? await Services.yt.comments(widget.videoId)
          : await Services.yt.commentsContinuation(_token!);
      if (!mounted) return;
      setState(() {
        _comments.addAll(page.comments);
        _token = page.continuation;
        _done = page.continuation == null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _done = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Text(_loading ? 'Loading…' : 'No comments', style: const TextStyle(fontSize: 24, color: Tv.text2)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      itemCount: _comments.length,
      itemBuilder: (context, i) {
        final c = _comments[i];
        if (i >= _comments.length - 5 && !_done && !_loading) {
          _loading = true;
          _load();
        }
        return TvFocusable(
          autofocus: i == 0,
          builder: (context, focused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: focused ? const Color(0x14FFFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipOval(child: NetImage(c.authorAvatar, width: 56, height: 56)),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text([c.author, ?c.published].join(' • '), style: const TextStyle(fontSize: 20, color: Tv.text2)),
                      const SizedBox(height: 6),
                      Text(c.text, style: const TextStyle(fontSize: 24, height: 1.4)),
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (c.likes != null && c.likes!.isNotEmpty) '👍 ${c.likes}',
                          if (c.replyCount > 0) '${c.replyCount} replies',
                        ].join('   '),
                        style: const TextStyle(fontSize: 20, color: Tv.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

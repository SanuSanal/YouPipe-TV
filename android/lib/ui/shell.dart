import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/account.dart';
import '../screens/account.dart';
import '../screens/home.dart';
import '../screens/library.dart';
import '../screens/search.dart';
import '../screens/settings.dart';
import '../screens/subscriptions.dart';
import 'cards.dart';
import 'focusable.dart';
import 'overlay.dart';
import 'theme.dart';

/// Arrow keys a widget left alone move focus to the nearest stop in that direction; [onEdge] gets the ones that
/// found nothing (the Shell turns Left into the menu). With [spatial] off, [onEdge] gets every arrow.
class TvKeys extends StatelessWidget {
  const TvKeys({super.key, required this.child, this.onEdge, this.spatial = true});

  final Widget child;
  final bool Function(TraversalDirection dir)? onEdge;
  final bool spatial;

  static TraversalDirection? direction(LogicalKeyboardKey k) => switch (k) {
    LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
    LogicalKeyboardKey.arrowRight => TraversalDirection.right,
    LogicalKeyboardKey.arrowUp => TraversalDirection.up,
    LogicalKeyboardKey.arrowDown => TraversalDirection.down,
    _ => null,
  };

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (node, e) {
      if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
      final dir = direction(e.logicalKey);
      final focused = FocusManager.instance.primaryFocus;
      if (dir == null || focused == null) return KeyEventResult.ignored;
      if (spatial && focused.focusInDirection(dir)) return KeyEventResult.handled;
      onEdge?.call(dir);
      return KeyEventResult.handled;
    },
    child: child,
  );
}

/// The left menu, like YouTube on TV: a rail of icons that opens with labels while it has focus. One stop for the
/// remote: Up and Down move inside it, OK opens a section, Right goes back to the screen.
class NavRail extends StatefulWidget {
  const NavRail({
    super.key,
    required this.sections,
    required this.active,
    required this.onOpen,
    required this.onExit,
    required this.focusNode,
  });

  final List<(String, String, IconData)> sections;
  final String active;
  final ValueChanged<String> onOpen;
  final VoidCallback onExit;
  final FocusNode focusNode;

  @override
  State<NavRail> createState() => _NavRailState();
}

class _NavRailState extends State<NavRail> {
  int _index = 1;
  bool _focused = false;
  late final _select = SelectHandler(() => widget.onOpen(widget.sections[_index].$1), null);

  @override
  void dispose() {
    _select.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    return Focus(
      focusNode: widget.focusNode,
      skipTraversal: true,
      onFocusChange: (f) => setState(() {
        _focused = f;
        if (f) _index = sections.indexWhere((s) => s.$1 == widget.active).clamp(0, sections.length - 1);
      }),
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent || e is KeyRepeatEvent) {
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.arrowUp && _index > 0) {
            setState(() => _index--);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowDown && _index < sections.length - 1) {
            setState(() => _index++);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowRight) {
            widget.onExit();
            return KeyEventResult.handled;
          }
          if (TvKeys.direction(k) != null) return KeyEventResult.handled;
        }
        return _select.handle(e);
      },
      // Opens with a transform and opacity only; animating its width and a large blurred shadow stuttered on the
      // Samsung TV (docs/ui.md), and is just as costly for a TV's GPU here. The rail is always open-width: its panel
      // slides out from behind the icons, and the Shell fades a dim layer over the screen.
      child: SizedBox(
        width: Tv.navOpenWidth,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSlide(
                offset: _focused ? Offset.zero : const Offset(-(Tv.navOpenWidth - Tv.navWidth) / Tv.navOpenWidth, 0),
                duration: Tv.slide,
                curve: Curves.easeOut,
                child: const ColoredBox(color: Tv.bg),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The account and the YouPipe name sit in the top bar, above the rail.
                  const SizedBox(height: 120),
                  for (var i = 0; i < sections.length; i++) ...[
                    if (i == sections.length - 1) const Spacer(),
                    _item(sections[i], i),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item((String, String, IconData) s, int i) {
    final focused = _focused && i == _index;
    final active = s.$1 == widget.active;
    final color = focused ? Tv.focusFg : (active ? Tv.text : Tv.text2);
    return GestureDetector(
      onTap: () => widget.onOpen(s.$1),
      // The same size open or closed (only the focused one, in the open menu, has a fill), so opening lays nothing out.
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        height: 72,
        width: Tv.navOpenWidth - 32,
        // Closed, the icon sits in the middle of the rail.
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: focused ? Tv.focusBg : Colors.transparent,
          borderRadius: BorderRadius.circular(36),
        ),
        child: Row(
          children: [
            Icon(s.$3, size: 36, color: color),
            const SizedBox(width: 28),
            AnimatedOpacity(
              opacity: _focused ? 1 : 0,
              duration: Tv.slide,
              child: Text(s.$2, style: TextStyle(fontSize: 28, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's frame: the left menu, the top bar and the sections (the account, Search, Home, Subscriptions, Library,
/// Settings). A section is built when first opened and kept, so coming back keeps its place. Back goes to Home, then
/// asks to exit. A splash covers it all until Home has its first row.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  /// The menu's sections; the account opens from the top bar.
  static const sections = [
    ('search', 'Search', Icons.search),
    ('home', 'Home', Icons.home_filled),
    ('subscriptions', 'Subscriptions', Icons.subscriptions_outlined),
    ('library', 'Library', Icons.video_library_outlined),
    ('settings', 'Settings', Icons.settings_outlined),
  ];
  static const _keys = ['account', 'search', 'home', 'subscriptions', 'library', 'settings'];

  /// The sections with the top bar above them.
  static const _withTopbar = {'home', 'subscriptions', 'library'};
  static const _system = MethodChannel('youpipe/system');

  final _nav = FocusNode(debugLabel: 'nav');
  // Left from a screen goes to the menu, never to the top bar: only Up reaches the bar (below), and the bar moves
  // between its two stops itself.
  final _topAccount = FocusNode(debugLabel: 'top account', skipTraversal: true);
  final _topSearch = FocusNode(debugLabel: 'top search', skipTraversal: true);
  final _roots = {for (final k in _keys) k: FocusNode(debugLabel: k, skipTraversal: true)};
  final _visited = <String>{'home'};
  final _lastFocus = <String, FocusNode>{};

  /// How far each section's page has scrolled; the top bar moves up with it.
  final _scrolled = <String, double>{};
  final _topbarY = ValueNotifier<double>(0);
  String _active = 'home';

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_remember);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_remember);
    _nav.dispose();
    _topAccount.dispose();
    _topSearch.dispose();
    _topbarY.dispose();
    for (final n in _roots.values) {
      n.dispose();
    }
    super.dispose();
  }

  bool get _topbarShown => _withTopbar.contains(_active);
  bool get _inTopbar => _topAccount.hasFocus || _topSearch.hasFocus;

  /// Remembers where focus was in each section, for Right from the menu.
  void _remember() {
    final f = FocusManager.instance.primaryFocus;
    final root = _roots[_active];
    if (f != null && root != null && f != root && f.ancestors.contains(root)) _lastFocus[_active] = f;
  }

  void open(String key) {
    setState(() {
      _active = key;
      _visited.add(key);
    });
    _topbarY.value = _scrolled[key] ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => focusScreen());
  }

  /// Focus back into the open section: where it was, or its first stop.
  void focusScreen() {
    final last = _lastFocus[_active];
    if (last != null && last.context != null && last.canRequestFocus) {
      last.requestFocus();
      return;
    }
    final root = _roots[_active]!;
    final first = root.traversalDescendants.where((n) => n.canRequestFocus && n.context != null).firstOrNull;
    if (first != null) {
      first.requestFocus();
    } else {
      _nav.requestFocus();
    }
  }

  Widget _section(String key) => switch (key) {
    'account' => const AccountScreen(),
    'search' => const SearchScreen(),
    'home' => const HomeScreen(),
    'subscriptions' => const SubscriptionsScreen(),
    'library' => const LibraryScreen(),
    _ => const SettingsScreen(),
  };

  void _back() {
    if (_nav.hasFocus || _inTopbar) return focusScreen();
    if (_active != 'home') return open('home');
    showConfirm(
      context,
      'Exit YouPipe?',
      'Exit',
      () => _system.invokeMethod<void>('exit').catchError((_) => SystemNavigator.pop()),
    );
  }

  /// The open section's page scrolled (not a row sliding sideways): the top bar follows it.
  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      _scrolled[_active] = n.metrics.pixels;
      _topbarY.value = n.metrics.pixels;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Material(
      color: Tv.bg,
      child: Stack(
        children: [
          Positioned.fill(
            left: Tv.navWidth,
            child: TvKeys(
              onEdge: (dir) {
                if (dir == TraversalDirection.left) _nav.requestFocus();
                // Up from a section's first row reaches the top bar's search box.
                if (dir == TraversalDirection.up && _topbarShown) _topSearch.requestFocus();
                return true;
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: Stack(
                  children: [
                    for (final k in _keys)
                      if (_visited.contains(k))
                        Offstage(
                          offstage: k != _active,
                          child: ExcludeFocus(
                            excluding: k != _active,
                            child: Focus(
                              focusNode: _roots[k],
                              skipTraversal: true,
                              child: FocusTraversalGroup(child: _section(k)),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
          // Dims the screen while the menu is open: a plain colour, which needs no painting to fade.
          Positioned.fill(
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: _nav,
                builder: (context, _) => AnimatedOpacity(
                  opacity: _nav.hasFocus ? 1 : 0,
                  duration: Tv.slide,
                  child: const ColoredBox(color: Color(0xA6000000)),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: NavRail(sections: sections, active: _active, onOpen: open, onExit: focusScreen, focusNode: _nav),
          ),
          if (_topbarShown)
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: Tv.topbarHeight,
              child: ValueListenableBuilder<double>(
                valueListenable: _topbarY,
                builder: (context, y, child) => Transform.translate(offset: Offset(0, -y), child: child),
                child: TvKeys(
                  spatial: false,
                  // Left and Right move between the account and Search, Left from the account opens the menu,
                  // Down returns to the screen, and Up stops here.
                  onEdge: (dir) {
                    switch (dir) {
                      case TraversalDirection.left:
                        _topSearch.hasFocus ? _topAccount.requestFocus() : _nav.requestFocus();
                      case TraversalDirection.right:
                        if (_topAccount.hasFocus) _topSearch.requestFocus();
                      case TraversalDirection.down:
                        focusScreen();
                      case TraversalDirection.up:
                        break;
                    }
                    return true;
                  },
                  child: FocusTraversalGroup(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([Account.instance, _nav]),
                      builder: (context, _) => TopBar(
                        accountNode: _topAccount,
                        searchNode: _topSearch,
                        menuOpen: _nav.hasFocus,
                        onAccount: () => open('account'),
                        onSearch: () => open('search'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const Splash(),
        ],
      ),
    ),
  );
}

/// The bar above Home, Subscriptions and Library, like YouTube on TV: the account at the top left, then a search box
/// and the YouPipe name. It scrolls away with the page.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.accountNode,
    required this.searchNode,
    required this.menuOpen,
    required this.onAccount,
    required this.onSearch,
  });

  final FocusNode accountNode;
  final FocusNode searchNode;

  /// The open menu's shadow covers the screen; the search box steps back with it.
  final bool menuOpen;
  final VoidCallback onAccount;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final photo = Account.instance.signedIn ? Account.instance.info?.photo : null;
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 20),
          TvFocusable(
            focusNode: accountNode,
            scrollAlignment: null,
            onSelect: onAccount,
            builder: (context, focused) => AnimatedScale(
              scale: focused ? 1.08 : 1,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: focused ? Tv.focusBg : Colors.transparent, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: photo != null
                    ? ClipOval(child: NetImage(photo, width: 56, height: 56))
                    : Icon(Icons.account_circle_outlined, size: 48, color: focused ? Tv.focusFg : Tv.text2),
              ),
            ),
          ),
          const SizedBox(width: Tv.navWidth + Tv.pad - 92),
          AnimatedOpacity(
            opacity: menuOpen ? 0 : 1,
            duration: Tv.slide,
            child: TvFocusable(
              focusNode: searchNode,
              scrollAlignment: null,
              onSelect: onSearch,
              builder: (context, focused) => AnimatedScale(
                scale: focused ? 1.03 : 1,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 760,
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  decoration: BoxDecoration(
                    color: focused ? Tv.focusBg : Tv.surface,
                    borderRadius: BorderRadius.circular(36),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 36, color: focused ? Tv.focusFg : Tv.text2),
                      const SizedBox(width: 20),
                      Text('Search', style: TextStyle(fontSize: 28, color: focused ? Tv.focusFg : Tv.text2)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The YouPipe name sits at the far right.
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SvgPicture.asset('assets/logo.svg', width: 52, height: 52),
          ),
          const SizedBox(width: 16),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'YouPipe',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Tv.text),
            ),
          ),
          const SizedBox(width: Tv.pad),
        ],
      ),
    );
  }
}

/// The splash: the YouPipe mark until Home has its first row ([Splash.done]), at most 8 s. It continues the Android
/// launch screen (res/drawable/launch_background.xml).
class Splash extends StatefulWidget {
  const Splash({super.key});

  static final _done = ValueNotifier(false);

  /// Called by Home once a row has loaded, or Home has failed.
  static void done() => _done.value = true;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 8), Splash.done);
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: Splash._done,
      builder: (context, done, _) => IgnorePointer(
        ignoring: done,
        child: AnimatedOpacity(
          opacity: done ? 0 : 1,
          duration: const Duration(milliseconds: 400),
          onEnd: () {
            if (done && mounted) setState(() => _gone = true);
          },
          child: Container(
            color: Tv.bg,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset('assets/logo.svg', width: 168, height: 168),
                const SizedBox(width: 36),
                const Text(
                  'YouPipe',
                  style: TextStyle(fontSize: 88, fontWeight: FontWeight.w700, letterSpacing: -1.5, color: Tv.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

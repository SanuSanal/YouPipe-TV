import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../screens/home.dart';
import '../screens/library.dart';
import '../screens/search.dart';
import '../screens/settings.dart';
import '../screens/subscriptions.dart';
import 'focusable.dart';
import 'overlay.dart';
import 'theme.dart';

/// Arrow keys a widget left alone move focus to the nearest stop in that direction; [onEdge] gets the ones that
/// found nothing (the Shell turns Left into the menu).
class TvKeys extends StatelessWidget {
  const TvKeys({super.key, required this.child, this.onEdge});

  final Widget child;
  final bool Function(TraversalDirection dir)? onEdge;

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
      if (focused.focusInDirection(dir)) return KeyEventResult.handled;
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
      child: AnimatedContainer(
        duration: Tv.slide,
        curve: Curves.easeOut,
        width: _focused ? Tv.navOpenWidth : Tv.navWidth,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          color: Tv.bg,
          boxShadow: _focused
              ? const [BoxShadow(color: Color(0xD9000000), blurRadius: 160, spreadRadius: 40, offset: Offset(120, 0))]
              : null,
        ),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: Tv.navOpenWidth,
            minWidth: Tv.navOpenWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 28, bottom: 56),
                  child: Row(
                    children: [
                      SvgPicture.asset('assets/logo.svg', width: 56, height: 56),
                      const SizedBox(width: 18),
                      AnimatedOpacity(
                        opacity: _focused ? 1 : 0,
                        duration: Tv.slide,
                        child: const Text(
                          'YouPipe',
                          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Tv.text),
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < sections.length; i++) ...[
                  if (i == sections.length - 1) const Spacer(),
                  _item(sections[i], i),
                ],
              ],
            ),
          ),
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
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        height: 72,
        width: _focused ? Tv.navOpenWidth - 32 : Tv.navWidth - 32,
        // Collapsed, the icon sits in the middle of the 80-wide pill.
        padding: EdgeInsets.symmetric(horizontal: _focused ? 24 : 22),
        decoration: BoxDecoration(
          color: focused ? Tv.focusBg : Colors.transparent,
          borderRadius: BorderRadius.circular(36),
        ),
        child: Row(
          children: [
            Icon(s.$3, size: 36, color: color),
            if (_focused) ...[const SizedBox(width: 28), Text(s.$2, style: TextStyle(fontSize: 28, color: color))],
          ],
        ),
      ),
    );
  }
}

/// The app's frame: the left menu and the sections (Search, Home, Subscriptions, Library, Settings). A section is
/// built when first opened and kept, so coming back keeps its place. Back goes to Home, then asks to exit.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  static const sections = [
    ('search', 'Search', Icons.search),
    ('home', 'Home', Icons.home_filled),
    ('subscriptions', 'Subscriptions', Icons.subscriptions_outlined),
    ('library', 'Library', Icons.video_library_outlined),
    ('settings', 'Settings', Icons.settings_outlined),
  ];
  static const _system = MethodChannel('youpipe/system');

  final _nav = FocusNode(debugLabel: 'nav');
  final _roots = {for (final s in sections) s.$1: FocusNode(debugLabel: s.$1, skipTraversal: true)};
  final _visited = <String>{'home'};
  final _lastFocus = <String, FocusNode>{};
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
    for (final n in _roots.values) {
      n.dispose();
    }
    super.dispose();
  }

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
    'search' => const SearchScreen(),
    'home' => const HomeScreen(),
    'subscriptions' => const SubscriptionsScreen(),
    'library' => const LibraryScreen(),
    _ => const SettingsScreen(),
  };

  void _back() {
    if (_nav.hasFocus) return focusScreen();
    if (_active != 'home') return open('home');
    showConfirm(
      context,
      'Exit YouPipe?',
      'Exit',
      () => _system.invokeMethod<void>('exit').catchError((_) => SystemNavigator.pop()),
    );
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
                return true;
              },
              child: Stack(
                children: [
                  for (final s in sections)
                    if (_visited.contains(s.$1))
                      Offstage(
                        offstage: s.$1 != _active,
                        child: ExcludeFocus(
                          excluding: s.$1 != _active,
                          child: Focus(
                            focusNode: _roots[s.$1],
                            skipTraversal: true,
                            child: FocusTraversalGroup(child: _section(s.$1)),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: NavRail(sections: sections, active: _active, onOpen: open, onExit: focusScreen, focusNode: _nav),
          ),
        ],
      ),
    ),
  );
}

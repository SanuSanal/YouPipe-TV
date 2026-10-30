import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'focusable.dart';
import 'theme.dart';

/// A row of a side panel.
class PanelItem {
  const PanelItem(
    this.label, {
    this.sub,
    this.value,
    this.icon,
    this.checked = false,
    this.color,
    this.onSelect,
    this.keepOpen = false,
  });

  final String label;
  final String? sub;
  final String? value;
  final IconData? icon;
  final bool checked;
  final Color? color;
  final VoidCallback? onSelect;
  final bool keepOpen;
}

/// A row in a panel or a settings list: white while focused.
class PanelRow extends StatelessWidget {
  const PanelRow({super.key, required this.item, this.onSelect, this.autofocus = false});

  final PanelItem item;
  final VoidCallback? onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TvFocusable(
    autofocus: autofocus,
    onSelect: onSelect ?? item.onSelect,
    builder: (context, focused) {
      final fg = focused ? Tv.focusFg : Tv.text;
      final fg2 = focused ? const Color(0xFF444444) : Tv.text2;
      return Container(
        constraints: const BoxConstraints(minHeight: 80),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: focused ? Tv.focusBg : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            if (item.icon != null) ...[Icon(item.icon, size: 32, color: fg), const SizedBox(width: 22)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.label, style: TextStyle(fontSize: 26, color: fg)),
                  if (item.sub != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(item.sub!, style: TextStyle(fontSize: 20, color: fg2)),
                    ),
                ],
              ),
            ),
            if (item.value != null) Text(item.value!, style: TextStyle(fontSize: 22, color: fg2)),
            if (item.checked) Icon(Icons.check, size: 32, color: fg),
            if (item.color != null)
              Container(
                margin: const EdgeInsets.only(left: 12),
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
              ),
          ],
        ),
      );
    },
  );
}

Route<T> _overlayRoute<T>(Widget Function(BuildContext) builder) => PageRouteBuilder<T>(
  opaque: false,
  barrierColor: const Color(0x8C000000),
  barrierDismissible: true,
  transitionDuration: const Duration(milliseconds: 180),
  reverseTransitionDuration: const Duration(milliseconds: 120),
  pageBuilder: (context, a, b) => builder(context),
  transitionsBuilder: (context, a, b, child) => FadeTransition(opacity: a, child: child),
);

/// A side panel, like YouTube's settings sheet on TV. [content] builds custom rows (description, comments) instead
/// of [items]. Back closes it and focus returns where it was.
Future<void> showPanel(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<PanelItem> items = const [],
  Widget Function(BuildContext)? content,
  bool wide = false,
}) {
  final firstChecked = items.indexWhere((i) => i.checked);
  return Navigator.of(context).push(
    _overlayRoute(
      (ctx) => Stage(
        child: Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Tv.surface,
            child: SizedBox(
              width: wide ? 960 : 680,
              height: 1080,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(48, 56, 48, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w500, color: Tv.text),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(subtitle, style: const TextStyle(fontSize: 22, color: Tv.text2)),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: content != null
                        ? content(ctx)
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
                            children: [
                              for (var i = 0; i < items.length; i++)
                                PanelRow(
                                  item: items[i],
                                  autofocus: i == (firstChecked < 0 ? 0 : firstChecked),
                                  onSelect: () {
                                    if (!items[i].keepOpen) Navigator.of(ctx).pop();
                                    items[i].onSelect?.call();
                                  },
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A centred dialog with an action and Cancel; Cancel has focus. [cancel] renames Cancel, or leaves it out when null;
/// [focusAction] gives the action focus instead.
Future<void> showConfirm(
  BuildContext context,
  String message,
  String action,
  VoidCallback onConfirm, {
  String? detail,
  String? cancel = 'Cancel',
  bool focusAction = false,
}) => Navigator.of(context).push(
  _overlayRoute(
    (ctx) => Stage(
      child: Center(
        child: Material(
          color: Tv.surface,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            constraints: const BoxConstraints(minWidth: 640, maxWidth: 1040),
            padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w500, color: Tv.text),
                ),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(detail, style: const TextStyle(fontSize: 24, color: Tv.text2, height: 1.45)),
                  ),
                const SizedBox(height: 40),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TvButton(
                      label: action,
                      autofocus: focusAction || cancel == null,
                      onSelect: () {
                        Navigator.of(ctx).pop();
                        onConfirm();
                      },
                    ),
                    if (cancel != null) ...[
                      const SizedBox(width: 24),
                      TvButton(label: cancel, autofocus: !focusAction, onSelect: () => Navigator.of(ctx).pop()),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

/// The exit prompt over the whole screen, like YouTube on TV: the mark, the question, Stay and Exit stacked. Stay has
/// focus; Back stays too.
Future<void> showExitPrompt(BuildContext context, VoidCallback onExit) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Tv.bg,
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, a, b) => Stage(
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset('assets/logo.svg', width: 128, height: 128),
              const SizedBox(height: 40),
              const Text(
                'Exit YouPipe?',
                style: TextStyle(fontSize: 56, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Tv.text),
              ),
              const SizedBox(height: 16),
              const Text('Press Back to keep watching', style: TextStyle(fontSize: 26, color: Tv.text2)),
              const SizedBox(height: 64),
              _ExitButton(label: 'Stay', autofocus: true, onSelect: () => Navigator.of(ctx).pop()),
              const SizedBox(height: 20),
              _ExitButton(
                label: 'Exit',
                onSelect: () {
                  Navigator.of(ctx).pop();
                  onExit();
                },
              ),
            ],
          ),
        ),
      ),
    ),
    transitionsBuilder: (context, a, b, child) {
      final curve = CurvedAnimation(parent: a, curve: const Cubic(0.2, 0, 0, 1));
      return FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(curve),
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curve), child: child),
        ),
      );
    },
  ),
);

class _ExitButton extends StatelessWidget {
  const _ExitButton({required this.label, required this.onSelect, this.autofocus = false});

  final String label;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TvFocusable(
    autofocus: autofocus,
    onSelect: onSelect,
    scrollAlignment: null,
    builder: (context, focused) => AnimatedScale(
      scale: focused ? 1.05 : 1,
      duration: const Duration(milliseconds: 150),
      child: Container(
        width: 520,
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: focused ? Tv.focusBg : const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500, color: focused ? Tv.focusFg : Tv.text),
        ),
      ),
    ),
  );
}

/// A short message at the bottom of the screen.
abstract final class Toast {
  static OverlayEntry? _entry;
  static Timer? _timer;
  static final navigatorKey = GlobalKey<NavigatorState>();

  static void show(String message, {Duration duration = const Duration(seconds: 3)}) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _timer?.cancel();
    _entry?.remove();
    _entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: Stage(
          child: Align(
            alignment: const Alignment(0, 0.86),
            child: Material(
              color: Tv.focusBg,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: Tv.focusFg),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(duration, () {
      _entry?.remove();
      _entry = null;
    });
  }
}

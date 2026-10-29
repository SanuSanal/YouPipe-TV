import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keys pressed so far: screens use it to tell whether the user has moved since they loaded.
abstract final class KeyCounter {
  static int count = 0;

  static void install() => HardwareKeyboard.instance.addHandler((e) {
    if (e is KeyDownEvent) count++;
    return false;
  });
}

/// OK on the remote (DPAD_CENTER), Enter on a keyboard, A on a gamepad.
bool isSelectKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.gameButtonA;

/// OK activates on release; holding it opens options, like YouTube on TV. Shared by everything that takes OK.
class SelectHandler {
  SelectHandler(this.onSelect, this.onLongPress);

  VoidCallback? onSelect;
  VoidCallback? onLongPress;
  Timer? _timer;
  bool _fired = false;
  bool _down = false;

  static const longPress = Duration(milliseconds: 600);

  KeyEventResult handle(KeyEvent e) {
    if (!isSelectKey(e.logicalKey)) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      _down = true;
      _fired = false;
      _timer?.cancel();
      _timer = Timer(longPress, () {
        if (onLongPress != null && _down) {
          _fired = true;
          onLongPress!();
        }
      });
    } else if (e is KeyUpEvent) {
      _timer?.cancel();
      // A release without a press here (the press opened this screen) does nothing.
      if (_down && !_fired) onSelect?.call();
      _down = false;
    }
    return KeyEventResult.handled;
  }

  void dispose() => _timer?.cancel();
}

/// One stop for the remote: builds its child with whether it has focus, takes OK (and holding OK), and scrolls
/// itself into view when focused.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.builder,
    this.onSelect,
    this.onLongPress,
    this.onFocus,
    this.onKey,
    this.focusNode,
    this.autofocus = false,
    this.scrollAlignment = 0.3,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocus;
  final KeyEventResult Function(KeyEvent e)? onKey;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Where it sits in its scrolling list once focused; null leaves scrolling alone.
  final double? scrollAlignment;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;
  late final _select = SelectHandler(widget.onSelect, widget.onLongPress);

  @override
  void didUpdateWidget(TvFocusable old) {
    super.didUpdateWidget(old);
    _select
      ..onSelect = widget.onSelect
      ..onLongPress = widget.onLongPress;
  }

  @override
  void dispose() {
    _select.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.focusNode,
    autofocus: widget.autofocus,
    onFocusChange: (f) {
      setState(() => _focused = f);
      widget.onFocus?.call(f);
      final a = widget.scrollAlignment;
      if (f && a != null) {
        Scrollable.ensureVisible(
          context,
          alignment: a,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    },
    onKeyEvent: (node, e) {
      final r = widget.onKey?.call(e) ?? KeyEventResult.ignored;
      if (r != KeyEventResult.ignored) return r;
      return _select.handle(e);
    },
    child: GestureDetector(
      onTap: widget.onSelect,
      onLongPress: widget.onLongPress,
      child: widget.builder(context, _focused),
    ),
  );
}

/// A rounded button: white with dark text while focused.
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.label,
    this.icon,
    this.onSelect,
    this.autofocus = false,
    this.primary = false,
    this.on = false,
    this.focusNode,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onSelect;
  final bool autofocus;
  final bool primary;
  final bool on;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => TvFocusable(
    autofocus: autofocus,
    focusNode: focusNode,
    onSelect: onSelect,
    scrollAlignment: null,
    builder: (context, focused) => AnimatedScale(
      scale: focused ? 1.05 : 1,
      duration: const Duration(milliseconds: 150),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          color: focused
              ? const Color(0xFFF1F1F1)
              : (primary && !on ? const Color(0xFFFF0000) : const Color(0x1FFFFFFF)),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 32, color: focused ? const Color(0xFF0F0F0F) : Colors.white),
              const SizedBox(width: 12),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: focused ? const Color(0xFF0F0F0F) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/services.dart';
import 'ui/focusable.dart';
import 'ui/overlay.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KeyCounter.install();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await Services.init();
  runApp(const YouPipeTv());
}

/// YouPipe for Android TV and Google TV: the YouTube for TV layout on a 1920×1080 stage (docs/ui.md).
class YouPipeTv extends StatelessWidget {
  const YouPipeTv({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'YouPipe',
    debugShowCheckedModeBanner: false,
    theme: Tv.theme(),
    navigatorKey: Toast.navigatorKey,
    // Everything, panels and toasts included, is laid out on the stage.
    builder: (context, child) => _KeyboardBack(
      child: Stage(color: Colors.black, child: child!),
    ),
    home: const Shell(),
  );
}

/// Esc on a keyboard, and Backspace where nothing takes it (the search keyboard deletes with it), are the remote's
/// Back, as in the Samsung app.
class _KeyboardBack extends StatelessWidget {
  const _KeyboardBack({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (node, e) {
      final k = e.logicalKey;
      if (k != LogicalKeyboardKey.escape && k != LogicalKeyboardKey.backspace) return KeyEventResult.ignored;
      if (e is KeyDownEvent) Toast.navigatorKey.currentState?.maybePop();
      return KeyEventResult.handled;
    },
    child: child,
  );
}

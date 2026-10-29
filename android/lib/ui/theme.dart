import 'package:flutter/material.dart';

/// YouPipe TV's look, like YouTube on TV (docs/ui.md): dark, Roboto, YouPipe red. Sizes are in the 1920×1080 stage's
/// pixels (Stage), the same numbers as the Samsung app's stylesheet.
abstract final class Tv {
  static const bg = Color(0xFF0F0F0F);
  static const surface = Color(0xFF212121);
  static const surface2 = Color(0xFF2C2C2C);
  static const text = Color(0xFFF1F1F1);
  static const text2 = Color(0xFFAAAAAA);
  static const brand = Color(0xFFFF0000);
  static const focusBg = Color(0xFFF1F1F1);
  static const focusFg = Color(0xFF0F0F0F);

  static const navWidth = 96.0;
  static const navOpenWidth = 360.0;
  static const pad = 40.0;

  /// About 2.8 cards across a row, like YouTube on TV.
  static const cardWidth = 600.0;

  /// Grids (Subscriptions, See all, a channel's videos) fit three across.
  static const gridCardWidth = 540.0;

  /// The bar above Home, Subscriptions and Library (shell.dart); their first row starts below it.
  static const topbarHeight = 152.0;
  static const gap = 28.0;
  static const slide = Duration(milliseconds: 220);

  static const rowTitle = TextStyle(fontSize: 34, fontWeight: FontWeight.w500, color: text);
  static const cardTitle = TextStyle(fontSize: 30, height: 39 / 30, fontWeight: FontWeight.w500, color: text);
  static const cardMeta = TextStyle(fontSize: 24, height: 32 / 24, color: text2);

  /// Smaller cards (Search's results beside the keyboard).
  static const smallCardTitle = TextStyle(fontSize: 26, height: 34 / 26, fontWeight: FontWeight.w500, color: text);
  static const smallCardMeta = TextStyle(fontSize: 22, height: 29 / 22, color: text2);
  static const pageTitle = TextStyle(fontSize: 48, fontWeight: FontWeight.w500, color: text);

  static ThemeData theme() => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    colorScheme: const ColorScheme.dark(primary: brand, surface: surface),
    fontFamily: 'Roboto',
    // Focus is drawn by our own widgets.
    focusColor: Colors.transparent,
    hoverColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
  );
}

/// The 1920×1080 stage, scaled to the TV's logical size (Android TVs report 960×540 dp at 2×, so one stage pixel is
/// one screen pixel there).
class Stage extends StatelessWidget {
  const Stage({super.key, required this.child, this.color = Colors.transparent});

  final Widget child;

  /// Around the stage when the screen isn't 16:9; transparent for overlays.
  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Center(
      child: FittedBox(child: SizedBox(width: 1920, height: 1080, child: child)),
    ),
  );
}

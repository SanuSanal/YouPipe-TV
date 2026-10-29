import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'focusable.dart';
import 'theme.dart';

/// A key: what it types or does, and how many of the 7 columns it spans.
class _Key {
  const _Key(this.label, this.span, {this.icon, this.action});

  final String label;
  final int span;
  final IconData? icon;
  final String? action; // null: types [label]
}

/// The Search screen's keyboard, laid out like YouTube's on TV: letters in a 7-column grid, then Space, delete and
/// 123, then Clear and Search. One stop for the remote; the arrows move between keys and leave it at its edges.
class TvKeyboard extends StatefulWidget {
  const TvKeyboard({super.key, required this.text, required this.onChanged, required this.onSubmit, this.focusNode});

  final String text;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmit;
  final FocusNode? focusNode;

  @override
  State<TvKeyboard> createState() => _TvKeyboardState();
}

class _TvKeyboardState extends State<TvKeyboard> {
  static const _letters = ['abcdefg', 'hijklmn', 'opqrstu', "vwxyz-'"];
  static const _symbols = ['1234567', '890&#()', '@!?:~.,', r'/$%+=_"'];
  static const _cell = 80.0;
  static const _gapSize = 8.0;

  bool _symbolMode = false;
  int _row = 0;
  int _col = 0; // key index within the row
  bool _focused = false;
  late final _select = SelectHandler(_press, null);

  List<List<_Key>> get _rows => [
    for (final r in (_symbolMode ? _symbols : _letters)) [for (final c in r.split('')) _Key(c, 1)],
    [
      const _Key('Space', 3, icon: Icons.space_bar, action: 'space'),
      const _Key('', 2, icon: Icons.backspace_outlined, action: 'back'),
      _Key(_symbolMode ? 'ABC' : '123', 2, action: 'mode'),
    ],
    [const _Key('Clear', 2, action: 'clear'), const _Key('Search', 5, icon: Icons.search, action: 'search')],
  ];

  int _startColumn(List<_Key> row, int index) => row.take(index).fold(0, (a, k) => a + k.span);

  /// The key in [row] that covers column [column].
  int _keyAt(List<_Key> row, int column) {
    var c = 0;
    for (var i = 0; i < row.length; i++) {
      c += row[i].span;
      if (column < c) return i;
    }
    return row.length - 1;
  }

  void _press() {
    final k = _rows[_row][_col];
    final t = widget.text;
    switch (k.action) {
      case 'space':
        widget.onChanged('$t ');
      case 'back':
        if (t.isNotEmpty) widget.onChanged(t.substring(0, t.length - 1));
      case 'mode':
        setState(() => _symbolMode = !_symbolMode);
      case 'clear':
        widget.onChanged('');
      case 'search':
        widget.onSubmit(t);
      default:
        if (t.length < 100) widget.onChanged('$t${k.label}');
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      final rows = _rows;
      final k = e.logicalKey;
      if (k == LogicalKeyboardKey.arrowLeft) {
        if (_col == 0) return KeyEventResult.ignored;
        setState(() => _col--);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        if (_col >= rows[_row].length - 1) return KeyEventResult.ignored;
        setState(() => _col++);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
        final to = _row + (k == LogicalKeyboardKey.arrowUp ? -1 : 1);
        if (to < 0 || to >= rows.length) return KeyEventResult.ignored;
        final column = _startColumn(rows[_row], _col);
        setState(() {
          _col = _keyAt(rows[to], column);
          _row = to;
        });
        return KeyEventResult.handled;
      }
      // A real keyboard types too.
      final ch = e.character;
      if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32 && !isSelectKey(k)) {
        widget.onChanged('${widget.text}$ch');
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.backspace) {
        if (widget.text.isNotEmpty) widget.onChanged(widget.text.substring(0, widget.text.length - 1));
        return KeyEventResult.handled;
      }
    }
    return _select.handle(e);
  }

  @override
  void dispose() {
    _select.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7 * _cell + 6 * _gapSize,
            height: 80,
            margin: const EdgeInsets.only(bottom: 28),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF555555), width: 3)),
            ),
            alignment: Alignment.centerLeft,
            child: Text(
              widget.text.isEmpty ? 'Search YouTube' : '${widget.text}|',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 42, color: widget.text.isEmpty ? const Color(0xFF777777) : Tv.text),
            ),
          ),
          for (var r = 0; r < rows.length; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: _gapSize),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rows[r].length; i++) ...[
                    if (i > 0) const SizedBox(width: _gapSize),
                    _keyView(rows[r][i], _focused && r == _row && i == _col, () {
                      setState(() {
                        _row = r;
                        _col = i;
                      });
                      _press();
                    }),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _keyView(_Key k, bool focused, VoidCallback onTap) {
    final fg = focused ? Tv.focusFg : Tv.text;
    final width = k.span * _cell + (k.span - 1) * _gapSize;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 72,
        decoration: BoxDecoration(
          color: focused ? Tv.focusBg : (k.span > 1 ? const Color(0x0FFFFFFF) : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (k.icon != null) Icon(k.icon, size: 36, color: fg),
            if (k.icon != null && k.label.isNotEmpty) const SizedBox(width: 10),
            if (k.label.isNotEmpty)
              Text(
                k.label,
                style: TextStyle(fontSize: k.span > 1 ? 24 : 32, color: fg),
              ),
          ],
        ),
      ),
    );
  }
}

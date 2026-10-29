import 'package:flutter/material.dart';

import '../core/account.dart';
import '../core/home_rows.dart';
import '../core/library.dart';
import '../innertube/innertube.dart';
import '../ui/actions.dart';
import '../ui/cards.dart';
import '../ui/focusable.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';

class _Row {
  _Row(this.source);

  final RowSource source;
  List<YtItem> items = const [];
  bool loading = true;
  bool exhausted = false;
  bool fetchingMore = false;
  final focus = FocusNode();
}

/// Home: rows of videos that slide sideways (core/home_rows.dart says where each comes from).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<_Row> _rows = [];
  DateTime _builtAt = DateTime.now();
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    Library.instance.addListener(_onLibrary);
    Account.instance.addListener(_onAccount);
    _build();
  }

  @override
  void dispose() {
    Library.instance.removeListener(_onLibrary);
    Account.instance.removeListener(_onAccount);
    for (final r in _rows) {
      r.focus.dispose();
    }
    super.dispose();
  }

  /// After watching, Continue watching shows where each video got to (unless focus is in it). Home starts over
  /// when it's more than an hour old.
  void _onLibrary() {
    if (!mounted) return;
    if (DateTime.now().difference(_builtAt) > const Duration(hours: 1)) return _build();
    final row = _rows.where((r) => r.source.title == 'Continue watching').firstOrNull;
    if (row == null || row.focus.hasFocus) return;
    setState(() => row.items = [for (final h in Library.instance.continueWatching().take(30)) h.video]);
  }

  /// Signing in or out starts Home over with (or without) the account's recommendations.
  bool _signedIn = Account.instance.signedIn;

  void _onAccount() {
    if (!mounted || _signedIn == Account.instance.signedIn) return;
    _signedIn = Account.instance.signedIn;
    _build();
  }

  void _build() {
    _builtAt = DateTime.now();
    _keysAtBuild = KeyCounter.count;
    _failed = false;
    final rows = [for (final s in HomeRows.sources()) _Row(s)];
    setState(() => _rows = rows);
    runQueued([
      for (final r in rows)
        () async {
          try {
            final items = await r.source.load();
            if (!mounted) return;
            setState(() {
              r.items = items;
              r.loading = false;
            });
            if (items.isNotEmpty) Splash.done();
            _focusFirstIfIdle();
          } catch (e) {
            debugPrint('YouPipe: home row "${r.source.title}" failed: $e');
            if (mounted) setState(() => r.loading = false);
          }
        },
    ]).then((_) {
      if (mounted && _rows.every((r) => r.items.isEmpty)) setState(() => _failed = true);
      Splash.done();
    });
  }

  /// Until the user presses a key, focus sits on the top row that has loaded, so Home starts at its top row even
  /// when a lower row loads first.
  void _focusFirstIfIdle() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || KeyCounter.count != _keysAtBuild || !TickerMode.valuesOf(context).enabled) return;
    final first = _rows.where((r) => r.items.isNotEmpty).firstOrNull;
    if (first != null && !first.focus.hasFocus) first.focus.requestFocus();
  });

  int _keysAtBuild = 0;

  Future<void> _more(_Row r) async {
    final more = r.source.more;
    if (more == null || r.exhausted || r.fetchingMore) return;
    r.fetchingMore = true;
    try {
      final items = await more();
      if (!mounted) return;
      final seen = r.items.map((i) => i.id).toSet();
      setState(() {
        if (items.isEmpty) r.exhausted = true;
        r.items = [...r.items, ...items.where((i) => seen.add(i.id))];
      });
    } catch (e) {
      r.exhausted = true;
    } finally {
      r.fetchingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Couldn't load Home", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            const Text('Check the TV is online, then try again.', style: TextStyle(fontSize: 26, color: Tv.text2)),
            const SizedBox(height: 36),
            TvButton(label: 'Try again', autofocus: true, onSelect: _build),
          ],
        ),
      );
    }
    final visible = _rows.where((r) => r.loading || r.items.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tv.pad, Tv.topbarHeight, 0, 600),
      children: [
        for (final r in visible)
          TvRow(
            key: ObjectKey(r),
            title: r.source.title,
            items: r.items,
            loading: r.loading,
            focusNode: r.focus,
            actions: defaultActions(context),
            onNearEnd: () => _more(r),
          ),
      ],
    );
  }
}

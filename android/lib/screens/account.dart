import 'package:flutter/material.dart';

import '../core/account.dart';
import '../ui/cards.dart';
import '../ui/focusable.dart';
import '../ui/overlay.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';

/// The account, opened from the top of the menu like YouTube on TV. Signed out it offers Google's sign-in page;
/// signed in it shows who's signed in, imports the account's subscriptions and history, and signs out.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String? _imported;

  @override
  void initState() {
    super.initState();
    Account.instance.addListener(_changed);
  }

  @override
  void dispose() {
    Account.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The screen swaps its buttons on sign-in and sign-out, so focus moves to the new ones.
  void _refocus() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) context.findAncestorStateOfType<ShellState>()?.focusScreen();
  });

  Future<void> _signIn() async {
    final bool ok;
    try {
      ok = await Account.instance.signIn();
    } catch (e) {
      Toast.show("Couldn't open Google's sign-in page");
      debugPrint('YouPipe: sign-in failed: $e');
      return;
    }
    if (!ok) return;
    _refocus();
    final name = Account.instance.info?.name;
    Toast.show(name == null ? 'Signed in' : 'Signed in as $name');
    await _import();
  }

  Future<void> _import() async {
    if (Account.instance.importing) return;
    Toast.show('Importing from your account…');
    try {
      final (subs, videos) = await Account.instance.import();
      _imported = '$subs new subscriptions, $videos new videos in history';
      Toast.show('Imported $subs subscriptions and $videos videos from your history');
    } catch (e) {
      debugPrint('YouPipe: account import failed: $e');
      Toast.show("Couldn't import from your account");
    }
    if (mounted) setState(() {});
  }

  void _signOut() => showConfirm(context, 'Sign out?', 'Sign out', () async {
    await Account.instance.signOut();
    _imported = null;
    _refocus();
    Toast.show('Signed out');
  }, detail: 'Your library on this TV stays.');

  @override
  Widget build(BuildContext context) {
    final a = Account.instance;
    if (!a.signedIn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Tv.pad, 120, Tv.pad, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sign in to YouTube', style: Tv.pageTitle),
            const SizedBox(height: 28),
            const SizedBox(
              width: 1180,
              child: Text(
                'Bring your YouTube account to YouPipe: your recommendations on Home, your subscriptions and watch '
                'history, and your playlists, Watch later and liked videos in Library. Likes, subscriptions and '
                'Watch later go back to your account too.',
                style: TextStyle(fontSize: 28, height: 1.4, color: Tv.text),
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 1180,
              child: Text(
                "Google's sign-in page opens next. Type your email and password there with the remote, or with the "
                'keyboard in the Google TV app on your phone. The session stays on this TV.',
                style: TextStyle(fontSize: 24, height: 1.4, color: Tv.text2),
              ),
            ),
            const SizedBox(height: 48),
            TvButton(label: 'Sign in', icon: Icons.login, primary: true, onSelect: _signIn),
          ],
        ),
      );
    }
    final info = a.info;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tv.pad, 120, Tv.pad, 400),
      children: [
        Row(
          children: [
            ClipOval(child: NetImage(info?.photo, width: 128, height: 128)),
            const SizedBox(width: 36),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info?.name ?? 'Signed in', style: Tv.pageTitle),
                  if ((info?.handle ?? info?.email) != null) ...[
                    const SizedBox(height: 8),
                    Text(info!.handle ?? info.email!, style: const TextStyle(fontSize: 26, color: Tv.text2)),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 56),
        for (final item in [
          PanelItem(
            'Import subscriptions and watch history',
            sub: a.importing ? 'Importing…' : (_imported ?? 'Copies them from your account to this TV'),
            icon: Icons.download,
            onSelect: _import,
          ),
          PanelItem('Sign out', sub: 'Your library on this TV stays', icon: Icons.logout, onSelect: _signOut),
        ])
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: 1120, child: PanelRow(item: item)),
          ),
      ],
    );
  }
}

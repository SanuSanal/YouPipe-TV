import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/updates.dart';
import 'focusable.dart';
import 'overlay.dart';
import 'theme.dart';

const _system = MethodChannel('youpipe/system');

/// Offers [version]: Install downloads the APK for this TV and hands it to Android's installer, which asks to confirm
/// (and, the first time, to let YouPipe install apps). Later closes it (docs/release.md).
Future<void> offerUpdate(BuildContext context, String version) => showConfirm(
  context,
  'YouPipe $version is available',
  'Install',
  () => _install(version),
  detail: 'You have ${Updates.version}. Your history and subscriptions stay.',
  cancel: 'Later',
  focusAction: true,
);

Future<void> _install(String version) async {
  final nav = Toast.navigatorKey.currentState;
  if (nav == null) return;
  final file = File('${(await getTemporaryDirectory()).path}/update.apk');
  final abi = await _system.invokeMethod<String>('abi') ?? '';
  final cancel = CancelToken();
  final progress = ValueNotifier<(int, int)>((0, 0));
  final route = _progressRoute(version, progress);
  // Back or Cancel closes the dialog, which stops the download.
  route.popped.then((_) => cancel.cancel());
  nav.push(route);
  try {
    await Dio().download(
      Updates.apkUrl(version, abi),
      file.path,
      cancelToken: cancel,
      onReceiveProgress: (received, total) => progress.value = (received, total),
    );
  } catch (e) {
    if (route.isActive) nav.removeRoute(route);
    if (!(e is DioException && CancelToken.isCancel(e))) {
      Toast.show("Couldn't download the update");
      debugPrint('YouPipe: update download failed: $e');
    }
    return;
  }
  if (route.isActive) nav.removeRoute(route);
  final error = await _system.invokeMethod<String>('install', {'path': file.path});
  final context = nav.context;
  if (error == null || error == 'cancelled' || !context.mounted) return;
  if (error == 'signature') {
    showConfirm(
      context,
      "Couldn't install YouPipe $version",
      'OK',
      () {},
      detail:
          'It is signed differently from the YouPipe on this TV, so Android won\'t install it over it. Uninstall '
          'YouPipe, then install $version from sanusanal.github.io/YouPipe-TV. Uninstalling clears your history and '
          'subscriptions.',
      cancel: null,
    );
  } else {
    Toast.show("Couldn't install the update: $error");
  }
}

PageRouteBuilder<void> _progressRoute(String version, ValueNotifier<(int, int)> progress) => PageRouteBuilder<void>(
  opaque: false,
  barrierColor: const Color(0x8C000000),
  transitionDuration: const Duration(milliseconds: 180),
  pageBuilder: (ctx, a, b) => Stage(
    child: Center(
      child: Material(
        color: Tv.surface,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 880,
          padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
          child: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, p, _) {
              final (received, total) = p;
              int mb(int bytes) => (bytes / 1e6).round();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Downloading YouPipe $version',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w500, color: Tv.text),
                  ),
                  const SizedBox(height: 32),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: total > 0 ? received / total : null,
                      minHeight: 10,
                      color: Tv.brand,
                      backgroundColor: const Color(0x33FFFFFF),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    total > 0 ? '${mb(received)} of ${mb(total)} MB' : 'Starting…',
                    style: const TextStyle(fontSize: 24, color: Tv.text2),
                  ),
                  const SizedBox(height: 40),
                  TvButton(label: 'Cancel', autofocus: true, onSelect: () => Navigator.of(ctx).pop()),
                ],
              );
            },
          ),
        ),
      ),
    ),
  ),
  transitionsBuilder: (context, a, b, child) => FadeTransition(opacity: a, child: child),
);

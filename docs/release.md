# Releases and the website

## Cutting a release

1. Tag `main` with `vMAJOR.MINOR.PATCH` and push the tag. The version comes from the tag only; nothing in the code needs bumping.
2. `.github/workflows/release.yml` then:
   - **Samsung:** `npm ci` (which vendors Shaka Player, hls.js and Roboto), `npm test`, writes the version into `app/config.xml` and the `yp-version` meta tag, and zips `app/` as an **unsigned** `YouPipe-TV-v<version>-samsung.wgt`.
   - **Android:** `flutter analyze`, `flutter test`, then `YouPipe-TV-v<version>-android.apk` (every ABI) and `-arm64-v8a.apk`, `-armeabi-v7a.apk` (`--split-per-abi`). The version goes in as `--build-name` and `--dart-define=APP_VERSION` (Settings → Version).
   - creates the GitHub release with notes from the commit subjects since the last release, and install pointers.

## Signing

- **Samsung:** packages can't be signed for everyone: a Samsung TV only installs a package signed with a Samsung certificate that lists that TV. So the release is unsigned and each user signs it with their own certificate (`tizen package -t wgt -s <profile> -- <file>.wgt`), as the website explains. Checked 2026-10-29: the Tizen CLI signs an unsigned zip of `app/`.
- **Android:** with the repository secrets `ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` and `KEY_PASSWORD` set (the same keystore as YouPipe is fine; the application ids differ), every release is signed with that key, so updates install over the old version.
  - **Without them** the workflow signs with a throwaway debug key and warns; the APK installs, but each release then has to replace an uninstalled copy.
  - Local release builds read `android/android/key.properties` or the same env vars (`ANDROID_KEYSTORE_PATH` etc.); `key.properties` and `*.jks` are git-ignored.

## Updates

Both apps check `api.github.com/repos/SanuSanal/YouPipe-TV/releases/latest` (`Updates`: `lib/core/updates.dart`, `js/data/updates.js`) 3 s after Home loads, at most once a day, and whenever Settings → Version asks. A newer version is offered once in a prompt, only while Home is open with nothing over it; afterwards Settings → Version shows it. Builds without a version (`dev`) don't check by themselves.

- **Android installs it** (2026-10-30; this reverses "neither app can update itself"). Install downloads the release's APK for the TV's first ABI (`-arm64-v8a.apk`, `-armeabi-v7a.apk`, else the every-ABI `-android.apk`) into the app's cache, with progress and Cancel, and hands it to Android's `PackageInstaller` (`AppUpdater.kt`, permission `REQUEST_INSTALL_PACKAGES`). Android asks to confirm, and the first time to let YouPipe install apps. It only installs over the old app when both are signed with the same key: until the signing secrets above are set, every release has its own throwaway key, so the app says to uninstall and install from the website instead.
- **Samsung only notifies:** a Tizen app can't install packages, and the user signs each `.wgt` with their own certificate, so the prompt says to install it from a computer as the first time.

## Website

- `site/` (one static `index.html`, the logo and the preview image) is published by `.github/workflows/pages.yml` to https://sanusanal.github.io/YouPipe-TV/ when `site/**` changes on `main`.
- **One-time setup:** repo Settings → Pages → Source: **GitHub Actions**.
- It explains what the app is, its features and **how to install it**: Android TV (Downloader or adb) and Samsung (Tizen Studio, Developer Mode, a Samsung certificate, sign and install).
- The Android download buttons are filled in from the latest release through the GitHub API (asset names as above); without the API they point at the Releases page.
- Same look as YouPipe's site (Unbounded, Instrument Sans, porcelain/dark), with a TV mockup of Home drawn in CSS: made-up videos, no YouTube logos.

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

Neither app can update itself: Samsung only installs through Developer Mode, and the Android app has no installer permission. Settings → Version checks `api.github.com/repos/SanuSanal/YouPipe-TV/releases/latest` and says when there's a newer one.

## Website

- `site/` (one static `index.html`, the logo and the preview image) is published by `.github/workflows/pages.yml` to https://sanusanal.github.io/YouPipe-TV/ when `site/**` changes on `main`.
- **One-time setup:** repo Settings → Pages → Source: **GitHub Actions**.
- It explains what the app is, its features and **how to install it**: Android TV (Downloader or adb) and Samsung (Tizen Studio, Developer Mode, a Samsung certificate, sign and install).
- The Android download buttons are filled in from the latest release through the GitHub API (asset names as above); without the API they point at the Releases page.
- Same look as YouPipe's site (Unbounded, Instrument Sans, porcelain/dark), with a TV mockup of Home drawn in CSS: made-up videos, no YouTube logos.

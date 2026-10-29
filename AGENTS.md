# AGENTS.md

YouPipe TV: YouPipe for TVs, two native apps that each run fully on the TV. **Samsung** gets a Tizen web app (`samsung/`). **Android TV / Google TV** gets a Flutter app on YouPipe's core (InnerTube in Dart, NewPipeExtractor, ExoPlayer) (`android/`), not a WebView shell. It's the TV sibling of YouPipe (`D:\claude\YouPipe`, Flutter, Android phones) and has the same core features. It's for the owner's own TVs for now; distribution comes later.

**It's a TV app, not a phone app.** The UI copies the **YouTube for TV** app (the left menu, rows of large cards, the focused card growing, the TV player and on-screen keyboard), never YouTube Android, with YouPipe branding (the cylinder-in-a-screen logo). Every feature is designed for a remote on a 10-foot screen. Phone-only features (gestures, mini player, PiP, downloads, notifications) aren't ported unless they make sense on a TV. Both apps look and behave the same (docs/ui.md).

## Before planning or changing code

1. Read `docs/README.md`, then the doc for every area your task touches. At minimum, read `docs/architecture.md` and `docs/ui.md`.
2. Respect the decisions recorded in the docs. Don't reverse one silently. If a task needs to change one, say so to the user and update the doc.

Decisions that are easy to break by accident:

- **Everything runs on the TV.** InnerTube calls and stream playback go from the TV's own IP. Stream URLs are bound to the IP that requested them, so a server can't extract them for the TV. A host may serve the website and releases, never YouTube traffic.
- **Tokens and personal data stay on the TV.** Nothing about the user is sent to our servers.
- **A feature goes in both apps,** with the same design (docs/ui.md) and the same stored data (docs/data.md).
- **Samsung streams come from the VISIONOS client, with ANDROID's muxed 360p as the fallback** (docs/streaming.md). These are the clients NewPipeExtractor v0.26.5 uses, and their URLs need no cipher, `n` parameter or PO token. Don't switch to IOS (its URLs stop at about 1 MB on some videos) or to WEB/TVHTML5 (cipher, PO token) without testing past 1 MB.
- **Android streams come from NewPipeExtractor** through the copied YouPipe Kotlin channel; each stream source plays with its own client's User-Agent (YouPipe's docs/streaming.md).
- **Shaka Player plays VOD DASH; hls.js plays live HLS** on Samsung. YouTube's live audio is packed ADTS AAC, which Shaka misreads as TS (docs/streaming.md).
- **Only newer TVs:** Tizen 7.0+ (Chromium 94), Android 10+ (docs/platforms.md). Keep the Samsung JavaScript within Chromium 94. Use plain scripts, not ES modules: a packaged Tizen app loads them from the file system.
- **The UI must match YouTube for TV** (not YouTube Android), with YouPipe branding. Never ship YouTube logos or YouTube Sans.
- **No hosted web version and no WebView shell.** Each platform has its own app that runs on the TV (docs/architecture.md).

## After making changes

- **Update the docs in the same change** when you alter architecture, a decision, an endpoint, the UI's behaviour or stored data. Any added, removed or changed network call or platform channel goes in `docs/apis.md`, and every new origin also goes in `samsung/app/config.xml` and the dev server's allowlist.

## Working rules

- **Verification:**
  - Samsung (from `samsung/`): `npm test`; the self test (`npm run dev`, then http://localhost:8090/?selftest) when playback or InnerTube code changes; on a TV with `tools/tv.ps1 -SelfTest` (docs/testing.md).
  - Android (from `android/`): `dart format -l 120 lib test`, `flutter analyze` with no issues, `flutter test`; then the TV emulator (docs/testing.md).
  - On the device, use the SDK adb (`%LOCALAPPDATA%\Android\sdk\platform-tools\adb.exe`), not the "Minimal ADB" on PATH.
- **Secrets and personal data:**
  - Never commit certificates, `.sign/`, keystores, `key.properties`, cookies or signed-in responses.
  - Never type Google or Samsung credentials; the user signs in themselves.
- **Git:** commit only when asked. End commit messages with the attribution line the environment provides.

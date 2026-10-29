# Architecture

## Where things run

Two apps, each running fully on its TV. They share the design ([ui.md](ui.md)), the features, the data model ([data.md](data.md)) and these docs, not code (JavaScript vs Dart/Kotlin).

```
Samsung TV: Tizen web app (samsung/app)
  ├─ InnerTube (js/yt/innertube.js, parse.js) ── www.youtube.com/youtubei/v1
  │     WEB: search, browse, next, comments · VISIONOS/ANDROID: player (streams, captions, storyboards)
  ├─ Player (js/player/player.js, watch.js)
  │     VOD  → Manifest (js/yt/manifest.js) → Shaka Player (MSE) ── googlevideo, DASH SegmentBase ranges
  │     live → hls.js (MSE) ── manifest.googlevideo.com HLS
  │     kids → <video src> muxed 360p (ANDROID)
  ├─ Data (js/data/): settings, library, subscriptions feed, Home rows ── localStorage
  └─ UI (js/ui/, js/screens/) ── 1920×1080 stage, remote keys, spatial focus

Android TV / Google TV: Flutter app (android/)
  ├─ InnerTube in Dart (lib/innertube/, copied from YouPipe) ── search, browse, related, comments
  ├─ NewPipeExtractor (Kotlin, StreamExtractorChannel.kt) ── streams, captions, storyboards, chapters
  ├─ ExoPlayer through video_player (lib/player/) ── local DASH manifest, muxed via PlaybackProxy.kt, HLS
  ├─ Data (lib/core/) ── shared_preferences, the same keys and shapes as the Samsung app
  └─ UI (lib/ui/, lib/screens/) ── the same 1920×1080 stage design
```

GitHub Pages serves the website and GitHub Releases the packages ([release.md](release.md)). Nothing in between ever carries YouTube traffic.

## Folder map

| Path | Role |
|---|---|
| `samsung/app/` | The Tizen web app, packaged as is (`config.xml`, `index.html`, `css/`, `js/`) |
| `samsung/app/js/` | `core/` (log, net, store, format, platform), `yt/` (InnerTube, parsers, manifest, captions, storyboards, SponsorBlock/RYD, channel feeds), `data/`, `ui/` (dom, focus, router, left menu, cards, keyboard, overlays), `player/`, `screens/`, `selftest.js`, `app.js` |
| `samsung/app/lib/` | Shaka Player, hls.js and Roboto, copied from `node_modules` by `tools/vendor.mjs` on `npm install` (gitignored) |
| `samsung/tools/` | `dev-server.mjs` (desktop testing, `/proxy`), `tv.ps1` (build, sign, install, self test on a TV), `tv-selftest.mjs`, `vendor.mjs` |
| `samsung/test/` | `node --test` unit tests (parsers, manifest, storyboards, captions) |
| `android/` | The Flutter app: `lib/` (Dart), `android/` (Gradle, Kotlin channels, manifest), `test/` |
| `site/` | The website (GitHub Pages): what it is and how to install it |
| `assets/branding/` | The logo, shared by both apps and the site |
| `.github/workflows/` | `ci.yml` (tests), `release.yml` (packages on a version tag), `pages.yml` (the website) |

## Decisions (short ADRs)

1. **The whole app runs on the TV; no server in the middle** (2026-10-28). The alternative, running InnerTube on Cloudflare, fails for four reasons:
   - googlevideo URLs carry `ip=` and only play from that address, so a server would have to relay every byte of video.
   - Cloudflare restricts serving video it doesn't host.
   - Workers have no JVM for NewPipeExtractor and block `eval` for player JS.
   - All users would share Cloudflare's datacenter IPs, which YouTube bot-checks more often.
2. **No NewPipeExtractor on Samsung.** Tizen has no JVM. The Samsung app reuses what NewPipe does instead: the same InnerTube clients (VISIONOS for DASH, ANDROID for muxed), called from JavaScript (streaming.md). This reverses YouPipe's "streams from NewPipeExtractor" for the Samsung app only.
3. **A plain web app on Samsung, no framework or build step.** Classic `<script>` files: ES modules don't load from a packaged app's file system, and the code stays within Chromium 94 (platforms.md).
4. **One engine per stream type on Samsung** (streaming.md): Shaka for our DASH manifest, hls.js for live, and `<video src>` for muxed.
5. **The TV's access policy replaces CORS.** googlevideo and youtubei send no `Access-Control-Allow-Origin` for us. On Tizen, the origins listed in `config.xml` are allowed instead (verified on a Samsung TV, 2026-10-28, spike.md). In a desktop browser the dev server proxies them.
6. **YouTube for TV's design, YouPipe's branding.** It's a TV app: the YouTube for TV layout, built for the remote, never the phone app's (ui.md). Our cylinder mark, never YouTube logos or YouTube Sans.
7. **A native app per platform; no hosted web version and no WebView shell** (2026-10-28). Samsung runs the Tizen web app. Android TV runs a Flutter app on YouPipe's proven core (NewPipeExtractor, ExoPlayer).
8. **Android copies YouPipe's core rather than sharing a package** (2026-10-29), as YouPipe's own roadmap decided for its siblings: `lib/innertube/`, `video_info.dart`, `playback_proxy.dart` and the Kotlin `StreamExtractorChannel`, `PlaybackProxy`, `Googlevideo` and `MiniHttp` are copies. Fixes to them are copied across by hand.
9. **Both apps keep the same data model** (data.md): the same storage keys and JSON shapes, so the two apps behave alike and an export/import between them stays possible.
10. **Personal use first.** The apps are installed by hand (site, testing.md). A Samsung build only installs on TVs listed in the user's own certificate, so releases ship an unsigned `.wgt` that each user signs (release.md).
11. **Optional sign-in with Google's own page, never YouTube's TV credentials** (2026-10-29, account.md). Like YouPipe on phones, the user signs in on Google's page and the app uses the youtube.com session. Android TV: a native WebView for that page only (not a shell, decision 7), with full sync. Samsung: inside the app's web engine, read-only through youtube.com's pages. YouTube for TV's activation code isn't used: it needs YouTube's own app credentials.

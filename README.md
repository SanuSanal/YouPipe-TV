<p align="center"><img src="assets/branding/logo.svg" width="96" alt=""></p>

<h1 align="center">YouPipe TV</h1>

<p align="center">All of YouTube on your TV. None of the ads.<br>
For <b>Android TV / Google TV</b> and <b>Samsung TVs</b>.</p>

<p align="center">
  <a href="https://sanusanal.github.io/YouPipe-TV/"><b>Website and install guides</b></a> ·
  <a href="https://github.com/SanuSanal/YouPipe-TV/releases/latest">Download</a>
</p>

YouPipe TV is the TV sibling of [YouPipe](https://github.com/SanuSanal/YouPipe) (Android phones and tablets). It looks and works like YouTube's own TV app, built for the remote, and runs entirely on your TV: no ads, no server in between, and your history and subscriptions stay on the TV. Signing in to YouTube is optional: it brings your recommendations, history, playlists and subscriptions.

## Features

- The YouTube for TV layout: the left menu, rows of big cards, the TV keyboard, a full-screen player.
- Home built from what you watch and subscribe to, plus topic rows; Continue watching.
- Search with suggestions and recent searches.
- Up to 1080p, live streams, quick seeking with thumbnail previews and chapters.
- Captions, the description, chapters and comments in side panels.
- Subscriptions, Watch later, liked videos and saved playlists, kept on the TV.
- Optional YouTube sign-in on Google's own page: your recommendations, history, Watch later, liked videos and playlists, and your subscriptions and history copied to the TV.
- Optional SponsorBlock; Return YouTube Dislike counts.
- Autoplay and playlists (Play all, Shuffle).

## Install

| TV | Supported | Package |
|---|---|---|
| Android TV, Google TV | Android 10 or later | `YouPipe-TV-v…-android.apk` (or the smaller per-ABI APKs) |
| Samsung | 2023 models and later (Tizen 7.0+) | `YouPipe-TV-v…-samsung.wgt`, which you sign with your own Samsung certificate |

Step-by-step guides for both are on the [website](https://sanusanal.github.io/YouPipe-TV/#install). The apps aren't in the TV app stores.

## Repository

| Folder | What |
|---|---|
| [`samsung/`](samsung) | The Samsung app: a Tizen web app (plain JavaScript, Shaka Player, hls.js) |
| [`android/`](android) | The Android TV app: Flutter, with YouPipe's InnerTube client, NewPipeExtractor and ExoPlayer |
| [`site/`](site) | The website |
| [`docs/`](docs) | How it works and the decisions behind it: start at [docs/README.md](docs/README.md) |

<details>
<summary>Development</summary>

**Samsung app** (Node 22):

```bash
cd samsung
npm install
npm run dev     # http://localhost:8090, ?selftest runs the playback self test
npm test
```

On a TV: `.\tools\tv.ps1 -TvIp <TV-IP> -Profile <your Samsung certificate profile> -SelfTest` ([docs/testing.md](docs/testing.md)).

**Android TV app** (Flutter 3.47):

```bash
cd android
flutter pub get
flutter analyze
flutter test
flutter run     # on an Android TV emulator or a TV with adb
```

Releases are built by GitHub Actions from a `vMAJOR.MINOR.PATCH` tag ([docs/release.md](docs/release.md)).

</details>

## Disclaimer

YouPipe TV is not affiliated with, endorsed by or sponsored by YouTube, Google or Samsung. YouTube is a trademark of Google LLC; Samsung and Tizen are trademarks of Samsung Electronics.

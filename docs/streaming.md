# Streams

## Which InnerTube client (`InnerTube.player`)

The same clients as NewPipeExtractor v0.26.5 (YouPipe's `docs/streaming.md`). The constants were read from its `ClientsConstants`:

| Order | Client | Context | Used for |
|---|---|---|---|
| 1 | `VISIONOS` 1.02 (id 101) | `deviceMake: Apple`, `deviceModel: RealityDevice14,1`, `osName: visionOS`, `osVersion: 25.6.0.23O471`, `platform: MOBILE` | DASH (`adaptiveFormats`), live HLS (`hlsManifestUrl`) |
| 2 | `ANDROID` 21.03.36 (id 3) | `osName: Android`, `osVersion: 15`, `androidSdkVersion: 35` | Muxed 360p (`formats`, itag 18) when VISIONOS refuses a video |

**Why VISIONOS** (probed 2026-10-28, from Ireland, signed out):
- Its formats carry plain `url`s: no `signatureCipher`, no `n` parameter, no `pot`.
- Range requests anywhere in the file return 206, including with a Tizen browser User-Agent and with no User-Agent. Throughput was 30–140 Mbit/s. A browser can't set the User-Agent, so this matters.
- The `/player` request itself works with a browser User-Agent and without the `X-YouTube-Client-*` headers.

**Why not the others:**

| Client | Result |
|---|---|
| `IOS` | Plain URLs, but on some videos (a made-for-kids one) every range past about 1 MB gets **403**: the PO-token cap |
| `TVHTML5` | "The page needs to be reloaded" |
| `WEB_EMBEDDED_PLAYER` | "This video is unavailable" |
| `ANDROID` adaptive formats | No plain URL, so only its muxed stream is used |

**Made-for-kids videos:** VISIONOS answers `UNPLAYABLE` "This video is not available". The ANDROID fallback plays them at 360p.

## The DASH manifest (`Manifest.build`)

The same shape as YouPipe's manifest builder:
- **Video:** one AdaptationSet of **H.264** Representations, one per height up to 1080p. Where a height comes twice, the higher frame rate wins, then the higher bitrate.
- **Audio:** the best AAC (`audio/mp4`) of the original track. DRC copies (`isDrc`, `xtags` "drc") are dropped.
- **Ranges:** each Representation has its `BaseURL` and `SegmentBase` (`indexRange`, `Initialization` from `initRange`). Shaka then requests bounded ranges, which googlevideo doesn't throttle.
- **Loading:** the manifest goes to Shaka as a `data:application/dash+xml;base64,…` URI.

## Playback engines (`Player`)

| Source | Engine | Why |
|---|---|---|
| VOD with plain DASH formats | **Shaka Player 4.16** (MSE) | ABR, SegmentBase/sidx, seeking |
| Live (`isLive` + `hlsManifestUrl`) | **hls.js 1.7** (full build, MSE) | The video renditions are MPEG-TS, but the audio is an **alternate rendition** (`EXT-X-MEDIA`, itags 233 HE-AAC and 234 AAC-LC), **packed ADTS AAC with an ID3 PRIV timestamp**. Shaka parses both as TS: video buffers, audio never appends, playback never starts. hls.js handles packed audio. Its **light build leaves out alternate audio**, so with it live played without sound (found on the TV, 2026-10-29); the self test now fails a stream without sound (`Player.hasAudio`) |
| Muxed (ANDROID itag 18) | `<video src>` | Progressive MP4. Media elements need no CORS |

Only one engine owns the `<video>` at a time: Shaka is attached for a VOD and detached in `Player.stop()`.

**Quality:** Settings' Video quality caps ABR (Shaka `abr.restrictions.maxHeight`, hls.js `autoLevelCapping`); the player's Quality panel fixes a height (`Player.setHeight`) or goes back to Auto.

## Captions, storyboards, chapters (Samsung)

- **Captions:** the VISIONOS response's `captions.playerCaptionsTracklistRenderer.captionTracks`. Their `baseUrl` + `&fmt=json3` loads without a PO token (probed 2026-10-29). `Captions.parseJson3` turns the events into cues; the player shows every cue active at the time (auto-generated tracks roll two lines). The default track: the caption language (or the TV's), a manual track before an auto-generated one.
- **Storyboards:** `storyboards.playerStoryboardSpecRenderer.spec`: `url|level|level…`, each level `w#h#count#cols#rows#intervalMs#name#sigh`. The largest level is used; `$L` is the level, `$N` its name, `$M` the sprite page, plus `&sigh=`. `Storyboard.frame` finds a time's sheet and position.
- **Chapters:** from `next`: the `macroMarkersListItemRenderer`s in `engagementPanels` (title, `onTap.watchEndpoint.startTimeSeconds`, thumbnail), deduplicated and sorted.

## Android TV

The Android app plays like YouPipe (its docs/streaming.md), with the same copied code:
- `StreamExtractorChannel.kt` (NewPipeExtractor v0.26.5) returns the video's info: a static DASH manifest (H.264 up to the chosen height, or hardware VP9 above 1080p), the muxed stream, the HLS URL, captions (WebVTT), storyboards and chapters.
- `PlayerService` (`lib/player/player_service.dart`, a cut-down YouPipe `VideoPlayerService`): live → HLS; else the manifest file through ExoPlayer with the DASH client's User-Agent, falling back to the muxed stream through `PlaybackProxy.kt` (1 MB ranges at full speed). A mid-play error re-resolves once.
- No background playback, notification, downloads or casting: it's a TV app.

## The dev proxy

In a desktop browser, `Net.viaProxy` is on. Then:
- InnerTube calls, Shaka segment requests (a custom `https` scheme plugin) and hls.js requests (`xhrSetup`) go through `/proxy?u=` on the dev server, which sends a Tizen User-Agent.
- The proxy runs on the same machine, so stream URLs stay on its IP.
- Muxed `<video src>` plays directly, as it would on the TV.

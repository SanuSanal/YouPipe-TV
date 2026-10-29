# Network calls

All calls are signed out and go straight from the TV. On Samsung, every origin below is also listed in `samsung/app/config.xml` (`<access origin>`), which replaces CORS there, and in the dev server's allowlist (`samsung/tools/dev-server.mjs`).

## YouTube (InnerTube, `www.youtube.com/youtubei/v1/…`)

| Call | Samsung | Android | Notes |
|---|---|---|---|
| `POST visitor_id` | `InnerTube.ensureVisitor` | `InnerTube.ensureVisitorData` | WEB. Cached as `yp.visitorData` |
| `POST search` | `InnerTube.search`, `searchMore` | `search`, `searchContinuation` | WEB. `params`: `EgJAAQ==` Live, `EgQIAxAB` this week's videos |
| `POST browse` `{browseId: UC…, params}` | `InnerTube.channel`, `browseMore` | `channel`, `browseContinuation` | WEB. Channel tabs and sort chips; `EgZ2aWRlb3PyBgQKAjoA` is the Videos tab |
| `POST browse` `{browseId: VL<id>}` | `InnerTube.playlist`, `playlistMore` | `playlist`, `browseContinuation` | WEB |
| `POST next` `{videoId}` | `InnerTube.next` (details, chapters, related, comments token), `nextMore` | `related`, `nextContinuation` | WEB |
| `POST next` `{continuation}` | `InnerTube.comments` | `comments`, `commentsContinuation` | WEB. Comment entities in `frameworkUpdates` |
| `POST player` | `InnerTube.player` | (NewPipeExtractor) | Samsung: VISIONOS, then ANDROID (streaming.md). Streams, captions, storyboards |
| `GET www.youtube.com/feeds/videos.xml?channel_id=` | `ChannelFeed.latest` | `SubsFeed.latest` | Subscriptions feed; 404 for some channels, then the Videos tab (data.md) |

## Media

| Call | Who | Notes |
|---|---|---|
| `GET *.googlevideo.com/videoplayback` (ranged) | Shaka / `<video>` (Samsung); ExoPlayer, `PlaybackProxy.kt` (Android) | DASH segments, muxed stream |
| `GET manifest.googlevideo.com/api/manifest/hls_*` | hls.js; ExoPlayer | Live |
| `GET www.youtube.com/api/timedtext?…&fmt=json3` | `Captions.load` (Samsung) | VISIONOS caption tracks, no PO token |
| Caption tracks (WebVTT) from NewPipe | `Captions.load` (Android) | |
| `GET i.ytimg.com/vi/…`, `i.ytimg.com/sb/…` | `<img>`, CSS; `Image.network` | Thumbnails, storyboards |
| `GET yt3.ggpht.com`, `yt3.googleusercontent.com` | the same | Avatars, channel banners |

## Others

| Call | Samsung | Android | Notes |
|---|---|---|---|
| `GET suggestqueries.google.com/complete/search?client=firefox&ds=yt` | `InnerTube.suggestions` | `suggestions` | Search suggestions |
| `GET sponsor.ajay.app/api/skipSegments/<sha256 prefix>` | `SponsorBlock.segments` | `SponsorBlock.segments` | Only when SponsorBlock is on; only 4 hex characters of the hash leave the TV |
| `GET returnyoutubedislikeapi.com/votes?videoId=` | `Dislikes.count` | `Dislikes.count` | Unless turned off |
| `GET api.github.com/repos/SanuSanal/YouPipe-TV/releases/latest` | Settings → Version | Settings → Version | Only when asked |

## Android platform channels

| Channel | Methods | Kotlin |
|---|---|---|
| `youpipe/stream_extractor` | `getVideoInfo {videoId, hl, gl, maxHeight}` | `StreamExtractorChannel` (copied from YouPipe) |
| `youpipe/playback_proxy` | `url {url, mimeType}` → loopback URL | `PlaybackProxy` (copied from YouPipe) |
| `youpipe/system` | `playing {playing}` (keep the screen on), `exit` | `MainActivity` |

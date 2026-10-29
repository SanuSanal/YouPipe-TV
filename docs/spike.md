# Spike: can YouPipe run entirely on a Tizen TV? (started 2026-10-28)

> History. The spike became the Samsung app (2026-10-29); its findings are in streaming.md and architecture.md, and file paths below are from before the move to `samsung/`.

**Question:** can the whole app (InnerTube, stream extraction, full-length playback) run inside a Tizen web app, with no server?

## Verdict: yes, it runs entirely on the TV

| Check | Where | Result |
|---|---|---|
| VISIONOS `/player` gives plain stream URLs (no cipher, `n` or PO token) | Node, PC in Ireland | **Yes**, for 4 of 4 videos. Made-for-kids videos are refused (ANDROID fallback, below) |
| Those URLs play past 1 MB with a **browser** User-Agent | Node | **Yes.** 206 at 50% and 95% of 80–258 MB files, 30–140 Mbit/s |
| `/player` and search work with a browser User-Agent and no client headers | Node | **Yes** |
| googlevideo / youtubei send CORS headers for us | Node | **No** (no `Access-Control-Allow-Origin`) |
| ...but the packaged app on the TV can call them anyway | Samsung TV | **Yes.** `fetch` to youtubei returns 200 with no proxy: the `config.xml` `<access>` list replaces CORS |
| Self test in desktop Chromium 152 (through the dev proxy) | Browser | **7/7 pass** |
| Self test on a Samsung TV (direct, no proxy) | UE43CU7020, Tizen 9.0 | **7/7 pass, twice.** Details below |
| Packaging | Tizen CLI 2.5.25 | **Builds and signs** (`YouPipe.wgt`, 410 KB) with an author certificate or a Samsung certificate |

### Self test on a Samsung TV, 2026-10-28

The TV: UE43CU7020KXXU (2023 Crystal UHD), Tizen **9.0** (Chromium 120, armv7). Signed with a Samsung certificate (Public privilege), run with `tv.ps1 -SelfTest`.

| Case | Result |
|---|---|
| visitor_id, search | OK; 18 videos |
| `aqz-KE-bpKQ` 10 min, from 75% | DASH, starts at 720p, settles at **1080p**, playing **4.5–6.1 s** after opening |
| `dQw4w9WgXcQ`, `9bZkp7q19f0`, from 75% | DASH, **1080p**, playing after **3.1–3.2 s** |
| `Scm5tqflAjE` (made for kids), from 75% | ANDROID muxed 360p, playing after 3.2–3.3 s |
| Live (found by the Live filter) | hls.js; starts at 144p, one `bufferStalledError` (hls.js recovers by itself), then 360–480p. Playing after 2.8–3.0 s |

- **`/player` is fast** (170–530 ms). Most of the start-up time is buffering on the TV, about 1–2 s more than on the PC.
- **The TV reports 4096×2160 at 60 fps and HDR.** The manifest stops at 1080p H.264 by choice (streaming.md); 4K would need VP9 or AV1.

### Self test, 2026-10-28 (desktop Chromium 152, through the dev proxy)

| Case | Result |
|---|---|
| visitor_id, search | OK; 19–20 videos |
| `aqz-KE-bpKQ` 10 min, from 75% | DASH, **1080p** (1920×1080), playing **1.4–2.6 s** after opening |
| `dQw4w9WgXcQ`, `9bZkp7q19f0`, from 75% | DASH, 1080p (one run settled at 720p), playing after 1.4–2.1 s |
| `Scm5tqflAjE` (made for kids), from 75% | VISIONOS `UNPLAYABLE`; **ANDROID muxed 360p**, playing after 1.7 s |
| Live (CBS News, found by the Live filter) | hls.js, **720p**, playing after 1.2–1.4 s |

## Problems found and fixed

1. **Live audio never played with Shaka.** YouTube's live HLS audio renditions are packed ADTS AAC with an ID3 timestamp, while the video is MPEG-TS. Shaka took both for TS. **Fix:** live plays through hls.js.
2. **IOS isn't a safe fallback.** On a made-for-kids video its URLs return 403 past about 1 MB. **Fix:** ANDROID muxed 360p, as in YouPipe.
3. **`video.play()` never settles on a stalled stream,** which hung the caller. **Fix:** play() isn't awaited.
4. **Grid overflow:** `1fr` columns grew to fit the `nowrap` meta line. **Fix:** `minmax(0, 1fr)`.

## Still open

1. **Older Tizen:** the test TV runs 9.0 (Chromium 120). Shaka and hls.js on Tizen 7.0 (Chromium 94) and 8.0 (108) are untested: MSE behaviour, 1080p decode, memory.
2. **Remote keys on real hardware:** Back (10009), media keys, and the IME's Done/Cancel (65376/65385). The self test was driven over the Web Inspector, not the remote.
3. **Start-up time:** 3–6 s on the TV. A lower `bufferingGoal` before the first frame, or starting at 480p, may help.
4. **The bot check** from a home IP over a longer session.

# Supported platforms

**Only newer TVs** (decision 2026-10-28). Older TVs aren't supported, even if the app installs on them.

| Platform | Minimum | Runtime | Notes |
|---|---|---|---|
| **Samsung** | 2023 models (**Tizen 7.0**) and later | Chromium 94 (Tizen 7.0), 108 (8.0), 120 (9.0), 130 (10.0) | From the 2023 models on, Samsung ships OS upgrades, so many 2023 TVs already run 8.0 or later. `config.xml` sets `required_version="7.0"`. The spike ran on a UE43CU7020 (Tizen 9.0) |
| **Android TV / Google TV** | **Android 10** (`minSdk 29`) | Flutter, NewPipeExtractor, ExoPlayer | A native app, like YouPipe; no WebView. Checked on the Android 16 TV emulator |

For now the app is for the owner's own TVs. Samsung installs need Developer Mode and a Samsung certificate listing each TV (testing.md); wider distribution is a later question.

Source for the Samsung mapping: Samsung's [Web Engine Specifications](https://developer.samsung.com/smarttv/develop/specifications/web-engine-specifications.html) and [General Specifications](https://developer.samsung.com/smarttv/develop/specifications/general-specifications.html).

## What the code may use

The Samsung app's floor is **Chromium 94**:
- **Fine:** `async`/`await`, optional chaining, `??`, `Array.prototype.at` (92), `aspect-ratio` (88), `inset` (87), MSE, `crypto.subtle` (the packaged app's `file://` origin is a secure context).
- **Not available:** `structuredClone` (98), CSS `:has()` (105), container queries (105), the `dvh` units (108).
- **No ES modules** in the packaged app: use classic scripts.
- **Codecs:** H.264 and AAC on every supported TV. VP9 and AV1 vary by model, so the manifest offers H.264 only for now.

# Testing

Before a change is done:
- **Samsung:** `cd samsung && npm test`; when playback or InnerTube code changes, the self test in a browser and on a TV.
- **Android:** `cd android && dart format -l 120 lib test && flutter analyze && flutter test`; then run it on the TV emulator or a TV.

## Samsung app

### Unit tests

```bash
npm test
```

From `samsung/`: the parsers, manifest builder, storyboards and captions (`test/*.test.mjs`), on synthetic responses.

### In a desktop browser

```bash
npm run dev
```

- Opens http://localhost:8090 (the `tv` entry in YouPipe's `.claude/launch.json` starts it too). The 1920×1080 stage scales to the window.
- **Keys:** arrows move focus, Enter is OK (hold it for a card's options), Esc/Backspace is Back, Space is play/pause, letters type in Search, `` ` `` shows the diagnostics log.
- **Self test:** http://localhost:8090/?selftest, or Settings → Run the self test. Each result is logged as `SELFTEST|<case>|PASS|FAIL|<detail>`; test plays don't go into the history. It runs:
  - `visitor_id`, a search and a watch page (`next`);
  - 3 VODs played from 75% of their length through the player screen, so well past the 1 MB cap;
  - a made-for-kids video (the ANDROID muxed fallback);
  - a live stream found through the Live search filter.
- **The proxy stands in for the TV.** A desktop browser enforces CORS, so every call goes through `/proxy` (streaming.md), which allows the same hosts as `config.xml`. A pass here doesn't prove the TV's access policy; only a TV run does.
- 2026-10-29: 8/8 in desktop Chromium 152, and every screen checked by hand with the keyboard (Home, Search, player with storyboard previews, info, comments and captions, channel, playlist with queue, Subscriptions, Library, Settings).

### On a Samsung TV

#### One-time setup

1. **Developer Mode on the TV:**
   1. Open **Apps** and type **1 2 3 4 5** on the remote (or the on-screen number pad).
   2. Turn **Developer mode** on and enter this PC's IP address.
   3. Restart the TV: hold the power button until it turns off and back on.
2. **Connect:** run `C:\tizen-studio\tools\sdb.exe connect <TV-IP>`, then `sdb devices`. The TV should be listed as `device`.
3. **A Samsung certificate.** The TV refuses packages signed only with the Tizen author certificate (`YouPipeTV-dev`, which only proves the package builds).
   - **An existing one works.** A Samsung certificate isn't tied to an app. It needs to be for **TV**, list the TV's DUID (`sdb -s <TV-IP>:26101 shell 0 getduid`) and not be expired. YouPipe TV only uses Public privileges.
   - **To make one:**
     1. Install **Samsung Certificate Extension** (Package Manager → Extension SDK) if your Tizen tools don't list a Samsung option.
     2. Open the Certificate Manager (Tizen Studio, or the VS Code Tizen extension) and create a **Samsung** certificate for **TV**.
     3. **Sign in with your own Samsung account. Do this yourself; agents never type credentials.**
     4. With the TV connected, the distributor certificate picks up the TV's DUID.
   - **Certificates made in the VS Code extension** are listed in its own `%USERPROFILE%\.tizen-extension-platform\server\sdktools\sdk-data\profile\profiles.xml`. `tv.ps1` uses Tizen Studio's CLI, which reads `C:\tizen-studio-data\profile\profiles.xml`. Copy the `<profile>` element across; it points at the same files.
   - The certificate in use on 2026-10-28 is `MyProject-Samsung`, valid until 2027-10-20, for one TV (UE43CU7020, Tizen 9.0).

#### Each run

From `samsung/`:

```powershell
.\tools\tv.ps1 -TvIp <TV-IP> -Profile MyProject-Samsung -SelfTest
```

- **What it does:** builds, signs and installs the app. Without `-SelfTest` it then launches it.
- **With `-SelfTest`:**
  1. Stops the app (`sdb shell 0 was_kill YouPipeTV1`), because `shell 0 debug` hangs while the app is running.
  2. Relaunches it with the Web Inspector and forwards the inspector port to this PC.
  3. Runs `tools/tv-selftest.mjs`, which starts the self test over the DevTools protocol and prints the app's `YP|` log lines.
  It exits 0 when every case passes, and takes about 2 minutes.
- **Web Inspector:** the script prints `http://127.0.0.1:<port>`. Open it in Chrome to debug. `node tools/tv-selftest.mjs <port> "<expression>"` evaluates an expression in the app.
- **By hand:** Settings → Run the self test. The red button toggles the log.
- **A release package:** `tizen package -t wgt -s <profile> -- <file>.wgt` signs an unsigned `.wgt` from GitHub Releases (checked 2026-10-29), then `tizen install -n <file>.wgt -s <TV-IP>:26101`.
- The spike's self test ran 7/7 on the TV on 2026-10-28 (spike.md). The full app ran 8/8 on the TV on 2026-10-29 (1080p DASH, muxed 360p, live).

## Android TV app

### Unit tests

```bash
flutter test
```

From `android/`: the library's JSON shapes and the WebVTT caption parser (`test/core_test.dart`).

### On the emulator

- The `YouPipe_TV` AVD (Android TV, x86_64). Use the SDK's adb (`%LOCALAPPDATA%\Android\sdk\platform-tools\adb.exe`), not the "Minimal ADB" on PATH.
- Build and install: `flutter build apk --debug --target-platform android-x64`, then `adb -e install -r build/app/outputs/flutter-apk/app-debug.apk` and `adb -e shell am start -n com.youpipe.tv/.MainActivity`.
- If videos show green or broken blocks (on this laptop the host GPU sometimes corrupts the emulator's decoder output, for every build), start it with `-gpu swiftshader_indirect`.
- Keys from the emulator window and its Extended controls D-pad don't reach the Android 16 TV image (emulator 37.2); adb key presses do. Its sound doesn't reach Windows either: Android plays at full volume but the emulator's stream is silent. The same APK on the Android 13 phone AVD plays with sound, so check sound there or on a TV.
- Drive it with `adb -e shell input keyevent DPAD_LEFT|DPAD_RIGHT|DPAD_UP|DPAD_DOWN|DPAD_CENTER|BACK`, type with `adb -e shell input text <text>` (Search's keyboard takes typed characters), and look with `adb -e exec-out screencap -p > shot.png`.
- 2026-10-29: Home rows, the left menu, Search (keyboard and suggestions), playback (DASH from VISIONOS through NewPipe), the player's controls, seeking with storyboard previews, Back, and Settings checked on the Android 16 TV emulator.
- 2026-10-30: Back from the menu (Home, then the exit prompt), Up next (the controls hide, the new list arrives), and DASH and live HLS through the SurfaceView checked on the TV emulator. Its decoder resizes its buffers on each quality change, so the green-area bug (streaming.md) only showed on a real TV.

### On a TV

`adb connect <TV-IP>:5555` (with network debugging on), then `adb install -r` the APK, as the website explains.

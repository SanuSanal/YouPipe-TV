# Google account (optional)

Everything works signed out. Signing in brings the account's recommendations, YouTube history, Watch later, liked videos and playlists, and copies its subscriptions and history to the TV.

**Never type the user's Google credentials** (AGENTS.md): the user signs in on Google's page themselves.

## How sign-in works

It's YouPipe's phone sign-in (`D:\claude\YouPipe\docs\account.md`): Google's own sign-in page, continuing to youtube.com, then the youtube.com session cookies. There's no OAuth client.

YouTube for TV's own activation code (youtube.com/activate) is **not used**: it only works with YouTube's TV app credentials, and taking those from YouTube's code would mean posing as YouTube's app (decided 2026-10-29).

### Android TV (`lib/core/account.dart`, `SignInActivity.kt`)

- **Sign-in:** the menu's top item (Sign in) → Account screen → **Sign in**, which opens `SignInActivity`.
  - That's a native WebView with Google's page (the same URL as YouPipe), so the remote and the TV's keyboard work in it.
  - Back steps back in the page, then cancels.
- **The cookie:**
  - When youtube.com loads with a `SAPISID` cookie, the activity returns `CookieManager.getCookie('https://www.youtube.com')` through `youpipe/account`. CookieManager can read it although the auth cookies are HttpOnly.
  - It's stored in `flutter_secure_storage` (`yt_cookie`).
- **Requests:** InnerTube adds `Cookie`, `Authorization: SAPISIDHASH …`, `X-Goog-AuthUser` and `X-Origin` (YouPipe's copied `lib/innertube/`).
- **Sync:** likes, Watch later and subscribe/unsubscribe also go to the account (`Library.remoteSync`). This is best-effort; the TV's library stays the source of truth.
- **Sign out:** deletes the cookie and clears the WebView's cookies.

### Samsung (`js/data/account.js`)

- **Sign-in:** the Account screen's **Sign in** navigates the app itself to Google's page. `config.xml` lists google.com, gstatic.com and googleapis.com in `<access>`.
  - **No `tizen:allow-navigation`:** the app reaches Google's page without it, and with it the TV refuses MediaSource `blob:` URLs (`MEDIA_ERR_SRC_NOT_SUPPORTED`), so no video plays (found on the TV, 2026-10-29).
  - The web engine keeps youtube.com's cookies.
  - Once YouTube's page shows, the user presses Back, or reopens YouPipe if Back does nothing.
  - **The remote can't move around Google's page:** the TV's web engine has no arrow-key navigation for pages, and no `config.xml` setting turns it on. The email box starts focused, but later steps (the 2-step code box, Next) can't be reached with the arrows. A USB mouse or keyboard on the TV works (Samsung enables the mouse in apps by default). On 2026-10-29 the code box was focused from the PC through the Web Inspector.
  - **Checks:** the app asks youtube.com (`Account.check`) on start when a sign-in or sign-out is pending (`yp.accountPending`), when it was signed in, or when it hasn't checked for a week (`Account.due`). Signed out, the Account screen also has **Already signed in? Check**.
  - Found signed in without a pending sign-in (the app's storage was cleared, or the page was opened another way), it imports as after a sign-in.
  - **Cookies only aren't enough for InnerTube:** `POST youtubei/v1/browse` with `credentials: 'include'` but no SAPISIDHASH answers `logged_in=0` (checked on the TV, 2026-10-29).
- **Requests: youtube.com's pages, not InnerTube.**
  - The app can't read the cookies (HttpOnly, another origin), so it can't compute SAPISIDHASH, and browsers forbid setting a `Cookie` header.
  - Instead it GETs youtube.com's desktop pages with `credentials: 'include'`: `/`, `/feed/history`, `/feed/playlists`, `/feed/channels` and `/playlist?list=WL|LL`, each with `app=desktop&persist_app=1`.
  - It reads their `ytInitialData`, the same JSON as an InnerTube browse response, with the existing parsers. `"LOGGED_IN":true` in the page says whether the TV is signed in.
  - Checked 2026-10-29: these pages answer the Tizen user agent with the desktop page and `ytInitialData`.
  - youtube.com sometimes sends Home as a placeholder grid (`ghostGridViewModel`) that its own script fills in, so `recommended()` fetches again when it gets fewer than 8 videos.
- **Read-only:** likes, Watch later and subscriptions changed in YouPipe stay on the TV.
  - Lists stop at their first page; youtube.com's playlist page holds 100 videos.
  - Playlists from YouTube playlists open through signed-out InnerTube, so private playlists don't open.
- **Sign out:** navigates to Google's Logout page, which clears the cookies the app can't touch.

## What signing in adds (both apps)

- **Home:** the account's YouTube Home as the Recommended row, in place of the one built from history (data.md). Android pages through it; Samsung shows its first page.
- **Library:** YouTube history, YouTube Watch later, YouTube liked videos and YouTube playlists rows, after the TV's own history.
- **Import:**
  - Right after signing in, and from the Account screen, the account's subscriptions and YouTube history are copied into the TV's library: `subs`, and `history` (data.md).
  - Imported history has no progress (YouTube doesn't say how far a video got) and goes after the TV's own entries.
  - Already-known channels and videos are skipped.
- **Not done:** watching in YouPipe doesn't add to the account's YouTube history. That would need the signed-in `/player` response's playback tracking, which neither app uses.

## Status (2026-10-29)

- **Android TV:** checked on the emulator up to Google's page.
  - The page opens and the remote moves around it; Back returns to YouPipe.
  - The signed-in calls are YouPipe's, which were checked with a real account on phones (2026-10-04).
  - Signing in on the TV itself is not tested yet.
- **Samsung (signed in on the user's TV, 2026-10-29):** works.
  - The menu shows the account photo; Home shows the account's recommendations.
  - Library: the YouTube history, Watch later, liked videos and playlists rows all load.
  - Import: the account's subscriptions and YouTube history came over to the TV.
  - The playback self test still passes 8/8.
  - Problems:
    - The remote can't reach the 2-step code box (above).
    - After the sign-in the app stayed on YouTube's page; it was reopened from the PC. Whether Back returns to YouPipe isn't confirmed.

# UI: YouTube for TV, YouPipe branding

Both apps copy the **YouTube for TV** app's layout and behaviour, never the phone app's (decision 6 in architecture.md). Every feature is built for a remote on a 10-foot screen. Phone-only features (gestures, mini player, PiP, downloads, notifications) aren't ported.

Both lay out a **1920×1080 stage** with the same pixel sizes:
- Samsung: `#stage`, scaled to the window in a desktop browser (`App.fitStage`);
- Android: `Stage` (a FittedBox around the whole MaterialApp). Android TVs report 960×540 dp at 2×, so one stage pixel is one screen pixel.

## Look

- Dark (`#0F0F0F`), Roboto (bundled on Samsung), YouPipe red `#FF0000` for the brand, the progress bar and the Subscribe button.
- **Focus:** a white ring and a 6% scale on the focused card; white fill with dark text on focused buttons, list rows, keyboard keys and menu items.
- Cards are 600 px wide (16:9 thumbnail, two-line 30 px title, channel, views • age): about 2.8 fit across a row, like YouTube on TV. Grids use 540 px cards, three across; Search's results beside the keyboard use 330 px cards with smaller text. A duration or LIVE badge, and a red progress line for videos in the history.

## Screens

| Screen | Layout |
|---|---|
| Splash | The YouPipe mark and name on the background colour until Home shows its first row (at most 8 s). Samsung: `#splash`; Android: the launch screen (`launch_background.xml`), then `Splash` in `shell.dart` |
| Top bar | Above Home, Subscriptions and Library (Samsung `topbar.js`, Android `TopBar` in `shell.dart`): a Search box from the content's left edge, then the YouPipe logo and name. It scrolls away with the page, and focusing the first row brings the page back to its top. Up from the first row reaches Search; Up stops there |
| Left menu | A rail of icons: the account at the top (its photo when signed in), level with the top bar's Search box, so it stays in place while the page and the top bar scroll; then Search, Home, Subscriptions, Library, and Settings at the bottom. While it has focus it opens to 360 px with labels, and a dim layer fades in over the screen; the top bar's search box fades out meanwhile. **It opens with transforms and opacity only:** the rail is always 360 px wide, its panel slides out from behind the icons, and the dim layer is one plain colour. On the Samsung TV (2026-10-29), animating the width and a large blurred shadow gave about 5 frames per opening, and a full-screen gradient cost a ~150 ms repaint; now about 20 frames. Cards likewise animate only their scale, not their shadow, and Samsung rows use CSS containment |
| Home | Rows that slide sideways: Continue watching, Recommended, Latest from your subscriptions, Because you watched…, then topic rows (Music, Live now, then shuffled topics). Grey placeholder cards while a row loads. Focus (and the splash) waits for the top row: a lower row that loads first doesn't take focus, so focus never jumps up when Recommended arrives later |
| Search | The keyboard on the left (7 columns: letters or 123, then Space/⌫/123, then Clear/Search); on the right, recent searches or suggestions while typing, and the results grid (3 across) after a search |
| Subscriptions | A row of the subscribed channels, then the latest videos as a grid |
| Library | Rows: History, Watch later, Liked videos, Saved playlists, Subscriptions. Long lists open in full in a grid |
| Channel | Banner, avatar, name, handle and counts, Subscribe; tabs Home (rows), Videos, Live, Playlists, Podcasts (grids, with Latest/Popular/Oldest chips) |
| Playlist | Details with Play all, Shuffle and Save on the left; the videos as a list on the right |
| Settings | A list; each row opens its choices in a side panel |
| Player | Full screen; see below |

## The remote

- **Arrows** move focus. In a row, Left/Right move along it and the focused card stays at the left; Up/Down go to the row above or below and **return to the card that row had last** (Samsung: `data-group`; Android: each row is one focus stop holding its own index). Grids move by cell and leave at their edges.
- **Left** from the first card opens the menu; **Right** from the menu returns to where focus was. Only Left enters the menu: Up and Down never do, even where a menu icon is nearer.
- **Up** from a section's first row goes to the top bar's Search (only Up reaches the top bar); Left there opens the menu; Down returns to the rows; Back returns to where focus was.
- **OK** activates on release. **Holding OK** (600 ms) on a card opens its options: Play, Save to/Remove from Watch later, Go to channel; in Library also "Remove from …"; on channels Subscribe/Unsubscribe; on playlists Save to Library.
- **Back:** closes a panel; then the open screen (player → previous screen); then goes Home; on Home it asks to exit.
- **Exit prompt** (Samsung `Overlay.exitPrompt`, Android `showExitPrompt`): like YouTube's on TV, it covers the screen in the solid background colour with the YouPipe mark, "Exit YouPipe?", "Press Back to keep watching", and two wide buttons stacked, Stay (focused) and Exit. Back stays. It fades and rises in with opacity and transforms only.
- **Media keys:** play/pause, play, pause, stop (leaves the player), fast-forward/rewind (seek), next/previous (and channel up/down) in the player.
- Samsung registers the media and colour keys (`Platform.registerKeys`); the **red** key toggles the diagnostics log.

## Player

- The video fills the screen; the controls fade in over a gradient and hide after 5 s while playing.
- **Hidden controls:** OK, Up or Down show them (focus on Play/Pause). Left/Right seek straight away: the seek bar takes focus and shows the preview.
- **Seek bar:** Left/Right move a pending position in 10 s steps, 30 s after 8 quick presses, 60 s after 20, with the storyboard frame, chapter name and time above the knob; it's applied 800 ms after the last press or on OK. Chapter ticks and SponsorBlock segments (in their category colours) are drawn on the bar. Up from the bar hides the controls.
- **Top:** title, channel avatar, name and subscribers, views • date.
- **Buttons:** previous, play/pause, next; then like (local, with YouTube's count), dislike (Return YouTube Dislike's estimate), Save (Watch later), Subscribe, captions, settings (quality, speed, captions, autoplay), info (chapters, then the description), comments, the channel.
- **Up next:** below the buttons; focusing it slides the controls up. The rest of a playlist when playing one, else related videos.
- **Autoplay:** at the end, a playlist plays its next video; otherwise, with Autoplay on, a 5 s "Up next" countdown (OK plays now, Back cancels).
- **Resume:** a video watched before resumes where it was (if more than 10 s in and more than 30 s from the end), with a toast.
- **SponsorBlock:** "skip" segments are skipped once each, with a "Skipped sponsor" toast.

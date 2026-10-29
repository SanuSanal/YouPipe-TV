# Data kept on the TV

Nothing about the user leaves the TV. Both apps use the **same keys and JSON shapes** (decision 9): Samsung in `localStorage` (`Store`, `js/core/store.js`), Android in shared preferences (`Store`, `lib/core/store.dart`), each key prefixed `yp.`.

| Key | Shape | Limit |
|---|---|---|
| `settings` | `{quality: 'auto'\|1080\|720\|480\|360, autoplay, captions, captionLang, speed, sponsorBlock, sbActions: {category: 'skip'\|'show'\|'off'}, dislikes, gl, hl}` | |
| `history` | `[{video, position, duration, at}]`, newest first; `position`/`duration` in seconds | 500 |
| `subs` | `[channel]` | 2000 |
| `watchLater`, `liked` | `[video]` | 500, 1000 |
| `playlists` | `[playlist]` (saved YouTube playlists) | 200 |
| `searches` | `[string]` | 30 |
| `subsFeed` | `{at, videos: [video + publishedAt]}` | 600 videos, 60 days |
| `visitorData` | InnerTube's anonymous session id | |

Items:
- **video** `{type: 'video', id, title, channel, channelId, avatar, thumb, duration, views, published, live, short}`
- **channel** `{type: 'channel', id, name, avatar, subs}`
- **playlist** `{type: 'playlist', id, title, thumb, channel, count}`

The Android app maps these to YouPipe's `VideoItem`/`ChannelItem`/`PlaylistItem` (`itemToJson`, `itemFromJson`).

## Home rows (`js/data/home.js`, `lib/core/home_rows.dart`)

Signed out, YouTube's own Home (`FEwhat_to_watch`) returns only a "start watching" nudge, so Home is built on the TV, like YouPipe's:

1. **Continue watching:** history entries more than 15 s in and less than 90% through (videos over a minute, not live).
2. **Recommended:** the related videos of the last 6 history videos, interleaved, without finished ones; pages through each seed's continuation.
3. **Latest from your subscriptions:** the cached feed (below), refreshed in the background.
4. **Because you watched <latest>:** that video's related videos.
5. **Topic rows:** searches limited to this week's videos (`params: EgQIAxAB`): Music, Live now (`EgJAAQ==`), then Gaming, News, Sports, Comedy, Science and tech, Cooking, Podcasts, Travel in a shuffled order.

Rows load three at a time; each pages on as focus nears its end. Shorts are left out. Home rebuilds after an hour; Continue watching updates after watching.

## Subscriptions feed (`js/data/subsfeed.js` + `js/yt/rss.js`, `lib/core/subs_feed.dart`)

- For each subscribed channel, six at a time, at most every 30 minutes (or right after subscribing to it):
  1. its Atom feed `feeds/videos.xml?channel_id=` (the 15 latest uploads with exact dates);
  2. if that fails (YouTube answers **404 for some channels**, found 2026-10-29), its Videos tab through InnerTube (`params: EgZ2aWRlb3PyBgQKAjoA`), with dates estimated from "3 days ago".
- A channel that can't be reached keeps what it had. Videos older than 60 days are dropped.

// The InnerTube parsers (app/js/yt/parse.js), storyboards and captions, on small synthetic responses.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const ctx = {};
for (const f of ['core/format.js', 'yt/parse.js', 'yt/storyboard.js', 'yt/captions.js']) {
  vm.runInNewContext(readFileSync(new URL('../app/js/' + f, import.meta.url), 'utf8'), ctx, { filename: f });
}
vm.runInNewContext('this.out = { Format, Parse, Storyboard, Captions };', ctx);
const { Format, Parse, Storyboard, Captions } = ctx.out;
const plain = (v) => JSON.parse(JSON.stringify(v));

const lockup = (id, parts, badges, type = 'LOCKUP_CONTENT_TYPE_VIDEO') => ({
  lockupViewModel: {
    contentId: id,
    contentType: type,
    contentImage: {
      thumbnailViewModel: {
        image: { sources: [{ url: `https://i.ytimg.com/vi/${id}/hq720.jpg`, width: 720 }] },
        overlays: [{ thumbnailBottomOverlayViewModel: { badges: badges.map((text) => ({ thumbnailBadgeViewModel: { text } })) } }],
      },
    },
    metadata: {
      lockupMetadataViewModel: {
        title: { content: 'Video ' + id },
        image: { decoratedAvatarViewModel: { avatar: { avatarViewModel: { image: { sources: [{ url: 'https://yt3.ggpht.com/a', width: 68 }] } } }, rendererContext: { commandContext: { onTap: { innertubeCommand: { browseEndpoint: { browseId: 'UCabc' } } } } } } },
        metadata: { contentMetadataViewModel: { metadataRows: parts.map((row) => ({ metadataParts: row.map((content) => ({ text: { content } })) })) } },
      },
    },
  },
});

test('lockups: parts are classified by what they say, short ages expanded', () => {
  const items = plain(Parse.items([lockup('a1', [['Some Channel'], ['1.2M views', '3mo ago']], ['12:34']), lockup('b2', [['Live Channel', '1.5K watching']], ['LIVE'])]));
  assert.equal(items.length, 2);
  assert.deepEqual(
    { channel: items[0].channel, channelId: items[0].channelId, views: items[0].views, published: items[0].published, duration: items[0].duration, live: items[0].live },
    { channel: 'Some Channel', channelId: 'UCabc', views: '1.2M views', published: '3 months ago', duration: '12:34', live: false },
  );
  assert.equal(items[1].live, true);
  assert.equal(items[1].views, '1.5K watching');
});

test('feed: shelves stay together, duplicates and ads are dropped, the continuation is found', () => {
  const data = {
    contents: [
      { videoRenderer: { videoId: 'v1', title: { runs: [{ text: 'One' }] }, lengthText: { simpleText: '3:00' }, ownerText: { runs: [{ text: 'Chan', navigationEndpoint: { browseEndpoint: { browseId: 'UCx' } } }] } } },
      { adSlotRenderer: { videoRenderer: { videoId: 'ad', title: { simpleText: 'Ad' } } } },
      { shelfRenderer: { title: { simpleText: 'People also watched' }, content: { items: [lockup('v2', [['C'], ['5 views', '1 day ago']], ['1:00']), { videoRenderer: { videoId: 'v1', title: { simpleText: 'dup' } } }] } } },
      { continuationItemRenderer: { continuationEndpoint: { continuationCommand: { token: 'TOKEN' } } } },
    ],
  };
  const page = plain(Parse.search(data));
  assert.equal(page.entries.length, 2);
  assert.equal(page.entries[0].item.channelId, 'UCx');
  assert.equal(page.entries[1].kind, 'shelf');
  assert.equal(page.entries[1].title, 'People also watched');
  assert.deepEqual(page.entries[1].items.map((i) => i.id), ['v2']);
  assert.equal(page.continuation, 'TOKEN');
  assert.deepEqual(plain(Parse.flatten(page.entries).map((i) => i.id)), ['v1', 'v2']);
});

test('playlist lockups become playlist items', () => {
  const pl = lockup('PL123', [['Playlist'], ['View full playlist']], [], 'LOCKUP_CONTENT_TYPE_PLAYLIST');
  pl.lockupViewModel.contentImage = {
    collectionThumbnailViewModel: { primaryThumbnail: { thumbnailViewModel: { image: { sources: [{ url: 'https://x/p.jpg', width: 1 }] }, overlays: [{ thumbnailOverlayBadgeViewModel: { thumbnailBadges: [{ thumbnailBadgeViewModel: { text: '16 videos' } }] } }] } } },
  };
  const [item] = plain(Parse.items([pl]));
  assert.deepEqual({ type: item.type, id: item.id, channel: item.channel, count: item.count }, { type: 'playlist', id: 'PL123', channel: null, count: '16 videos' });
});

test('watch page: details, chapters (once each, sorted), related and the comments token', () => {
  const marker = (title, start) => ({ macroMarkersListItemRenderer: { title: { simpleText: title }, timeDescription: { simpleText: Format.time(start) }, onTap: { watchEndpoint: { startTimeSeconds: start } } } });
  const data = {
    contents: {
      twoColumnWatchNextResults: {
        results: {
          results: {
            contents: [
              { videoPrimaryInfoRenderer: { title: { runs: [{ text: 'The title' }] }, viewCount: { videoViewCountRenderer: { viewCount: { simpleText: '1,000 views' }, shortViewCount: { simpleText: '1K views' } } }, dateText: { simpleText: 'Jan 1, 2026' } } },
              { videoSecondaryInfoRenderer: { owner: { videoOwnerRenderer: { title: { runs: [{ text: 'Owner', navigationEndpoint: { browseEndpoint: { browseId: 'UCowner' } } }] }, subscriberCountText: { simpleText: '10K subscribers' } } }, attributedDescription: { content: 'Hello\n\nWorld' } } },
              { itemSectionRenderer: { sectionIdentifier: 'comment-item-section', contents: [{ continuationItemRenderer: { continuationEndpoint: { continuationCommand: { token: 'COMMENTS' } } } }] } },
            ],
          },
        },
        secondaryResults: { secondaryResults: { results: [lockup('r1', [['C'], ['9 views']], ['2:00'])] } },
      },
    },
    engagementPanels: [{ p: { contents: [marker('Two', 60), marker('One', 0), marker('Two', 60)] } }],
  };
  const w = plain(Parse.watch(data));
  assert.equal(w.title, 'The title');
  assert.equal(w.viewsShort, '1K views');
  assert.deepEqual(w.channel.id, 'UCowner');
  assert.equal(w.channel.subs, '10K subscribers');
  assert.deepEqual(w.chapters.map((c) => [c.title, c.start]), [['One', 0], ['Two', 60]]);
  assert.deepEqual(w.related.map((r) => r.id), ['r1']);
  assert.equal(w.commentsToken, 'COMMENTS');
});

test('storyboard: the largest level, and frame positions in its sprite sheets', () => {
  const spec = 'https://i.ytimg.com/sb/ID/storyboard3_L$L/$N.jpg?sqp=abc|48#27#100#10#10#0#default#rs$A|160#90#120#5#5#2000#M$M#rs$B';
  const sb = plain(Storyboard.parse(spec, 240));
  assert.equal(sb.url, 'https://i.ytimg.com/sb/ID/storyboard3_L1/M$M.jpg?sqp=abc&sigh=rs$B');
  assert.deepEqual([sb.width, sb.height, sb.cols, sb.rows, sb.intervalMs], [160, 90, 5, 5, 2000]);
  const f = plain(Storyboard.frame(sb, 61)); // frame 30: page 1, index 5 → column 0, row 1
  assert.equal(f.url, 'https://i.ytimg.com/sb/ID/storyboard3_L1/M1.jpg?sqp=abc&sigh=rs$B');
  assert.deepEqual([f.x, f.y], [0, 90]);
  assert.equal(Storyboard.parse('', 10), null);
});

test('captions: json3 events, the lines active at a time, and the default track', () => {
  const cues = Captions.parseJson3({ events: [{ tStartMs: 0, dDurationMs: 2000, segs: [{ utf8: 'hello ' }, { utf8: 'there' }] }, { tStartMs: 1500, dDurationMs: 1000, segs: [{ utf8: 'world' }] }, { tStartMs: 5000 }] });
  assert.equal(cues.length, 2);
  assert.equal(Captions.at(cues, 1.6), 'hello there\nworld');
  assert.equal(Captions.at(cues, 4), '');
  const tracks = [{ lang: 'en', auto: true }, { lang: 'de', auto: false }, { lang: 'en-GB', auto: false }];
  assert.equal(Captions.pick(tracks, 'en'), tracks[2]);
  assert.equal(Captions.pick(tracks, 'fr'), tracks[1]);
});

test('format: times, counts and parsed durations', () => {
  assert.equal(Format.time(75), '1:15');
  assert.equal(Format.time(3725), '1:02:05');
  assert.equal(Format.parseTime('1:02:05'), 3725);
  assert.equal(Format.parseTime('LIVE'), null);
  assert.equal(Format.count(1234567), '1.2M');
  assert.equal(Format.count(18648), '18K');
  assert.equal(Parse.longAge('1y ago'), '1 year ago');
});

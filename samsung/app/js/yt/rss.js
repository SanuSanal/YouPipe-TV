// A channel's latest uploads, for the subscriptions feed (docs/data.md):
// - first its Atom feed (feeds/videos.xml, the 15 latest uploads with exact dates);
// - when that fails (YouTube answers 404 for some channels), its Videos tab through InnerTube, with relative dates.
var ChannelFeed = (function () {
  var VIDEOS_TAB = 'EgZ2aWRlb3PyBgQKAjoA';

  function parseAtom(xml, channelId, channelName) {
    var doc = new DOMParser().parseFromString(xml, 'application/xml');
    var NS_YT = 'http://www.youtube.com/xml/schemas/2015';
    var NS_MEDIA = 'http://search.yahoo.com/mrss/';
    return Array.prototype.map
      .call(doc.getElementsByTagName('entry'), (e) => {
        var id = (e.getElementsByTagNameNS(NS_YT, 'videoId')[0] || {}).textContent;
        if (!id) return null;
        var published = Date.parse((e.getElementsByTagName('published')[0] || {}).textContent || '') || Date.now();
        var stats = e.getElementsByTagNameNS(NS_MEDIA, 'statistics')[0];
        var link = e.getElementsByTagName('link')[0];
        var author = e.getElementsByTagName('author')[0];
        var name = author && author.getElementsByTagName('name')[0];
        return {
          type: 'video',
          id: id,
          title: (e.getElementsByTagName('title')[0] || {}).textContent || '',
          channel: (name && name.textContent) || channelName,
          channelId: channelId,
          thumb: Parse.thumbOf(id),
          views: stats ? Format.count(Number(stats.getAttribute('views'))) + ' views' : null,
          publishedAt: published,
          short: !!(link && /\/shorts\//.test(link.getAttribute('href') || '')),
          live: false,
        };
      })
      .filter(Boolean);
  }

  /** "3 days ago" → an approximate timestamp, so tab results sort with feed results. */
  function approxDate(text) {
    var m = /(\d+)\s+(second|minute|hour|day|week|month|year)/.exec(text || '');
    if (!m) return Date.now() - 365 * 864e5;
    var unit = { second: 1, minute: 60, hour: 3600, day: 86400, week: 604800, month: 2592000, year: 31536000 }[m[2]];
    return Date.now() - Number(m[1]) * unit * 1000;
  }

  async function latest(channelId, channelName) {
    try {
      var xml = await Net.getText('https://www.youtube.com/feeds/videos.xml?channel_id=' + channelId);
      var items = parseAtom(xml, channelId, channelName);
      if (items.length) return items;
    } catch (e) {
      // Fall through to the Videos tab.
    }
    var page = await InnerTube.channel(channelId, VIDEOS_TAB);
    return Parse.flatten(page.entries)
      .filter((i) => i.type === 'video')
      .slice(0, 15)
      .map((v) => Object.assign({}, v, { channel: v.channel || channelName, channelId: channelId, publishedAt: approxDate(v.published) }));
  }

  return { latest: latest, parseAtom: parseAtom };
})();

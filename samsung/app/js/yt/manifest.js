// A static DASH manifest from the player response, like YouPipe's StreamExtractorChannel:
// - one AdaptationSet of H.264 video, one Representation per height up to maxHeight;
// - the best AAC audio of the original track (DRC copies dropped);
// - each Representation has its own BaseURL and SegmentBase byte ranges (the formats' initRange/indexRange).
var Manifest = (function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function codecsOf(f) {
    var m = /codecs="([^"]+)"/.exec(f.mimeType);
    return m ? m[1] : '';
  }

  function segmentBase(f) {
    return (
      '<SegmentBase indexRange="' + f.indexRange.start + '-' + f.indexRange.end + '">' +
      '<Initialization range="' + f.initRange.start + '-' + f.initRange.end + '"/></SegmentBase>'
    );
  }

  function pickVideo(formats, maxHeight) {
    var byHeight = {};
    formats
      .filter((f) => f.url && f.initRange && f.indexRange && /^video\/mp4/.test(f.mimeType))
      .filter((f) => /avc1/.test(codecsOf(f)) && f.height <= maxHeight)
      .forEach((f) => {
        var best = byHeight[f.height];
        if (!best || (f.fps || 0) > (best.fps || 0) || ((f.fps || 0) === (best.fps || 0) && f.bitrate > best.bitrate)) {
          byHeight[f.height] = f;
        }
      });
    return Object.keys(byHeight)
      .map((h) => byHeight[h])
      .sort((a, b) => a.height - b.height);
  }

  function pickAudio(formats) {
    var aac = formats.filter((f) => f.url && f.initRange && f.indexRange && /^audio\/mp4/.test(f.mimeType));
    var main = aac.filter((f) => !f.isDrc && !(f.xtags && /drc/i.test(f.xtags)));
    var original = main.filter((f) => !f.audioTrack || f.audioTrack.audioIsDefault);
    var pool = original.length ? original : main.length ? main : aac;
    return pool.sort((a, b) => b.bitrate - a.bitrate)[0] || null;
  }

  /** Returns {mpd, heights} or null when the response has no DASH-able formats. */
  function build(info, maxHeight) {
    var videos = pickVideo(info.formats, maxHeight || 1080);
    var audio = pickAudio(info.formats);
    if (!videos.length || !audio) return null;
    var durationMs = Number(audio.approxDurationMs || videos[0].approxDurationMs || info.lengthSeconds * 1000);
    var out = [
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" type="static"' +
        ' minBufferTime="PT1.5S" mediaPresentationDuration="PT' + (durationMs / 1000).toFixed(3) + 'S">',
      '<Period>',
      '<AdaptationSet id="0" contentType="video" mimeType="video/mp4" subsegmentAlignment="true">',
    ];
    videos.forEach((f) => {
      out.push(
        '<Representation id="v' + f.itag + '" codecs="' + esc(codecsOf(f)) + '" bandwidth="' + f.bitrate + '"' +
          ' width="' + f.width + '" height="' + f.height + '" frameRate="' + (f.fps || 30) + '">' +
          '<BaseURL>' + esc(f.url) + '</BaseURL>' + segmentBase(f) + '</Representation>',
      );
    });
    out.push('</AdaptationSet>');
    out.push('<AdaptationSet id="1" contentType="audio" mimeType="audio/mp4" subsegmentAlignment="true">');
    out.push(
      '<Representation id="a' + audio.itag + '" codecs="' + esc(codecsOf(audio)) + '" bandwidth="' + audio.bitrate + '"' +
        ' audioSamplingRate="' + (audio.audioSampleRate || 44100) + '">' +
        '<AudioChannelConfiguration schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" value="' +
        (audio.audioChannels || 2) + '"/>' +
        '<BaseURL>' + esc(audio.url) + '</BaseURL>' + segmentBase(audio) + '</Representation>',
    );
    out.push('</AdaptationSet>', '</Period>', '</MPD>');
    return { mpd: out.join('\n'), heights: videos.map((f) => f.height) };
  }

  return { build: build };
})();

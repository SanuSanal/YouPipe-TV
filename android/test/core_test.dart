import 'package:flutter_test/flutter_test.dart';
import 'package:youpipe_tv/core/library.dart';
import 'package:youpipe_tv/innertube/models.dart';
import 'package:youpipe_tv/player/captions.dart';

void main() {
  group('library items', () {
    test('round-trip through the Samsung app JSON shape', () {
      const video = VideoItem(
        id: 'abc',
        title: 'A video',
        channelName: 'Chan',
        channelId: 'UCx',
        thumbnail: 'https://i.ytimg.com/vi/abc/hqdefault.jpg',
        durationText: '3:07',
        isLive: false,
      );
      final json = itemToJson(video);
      expect(json['type'], 'video');
      expect(json['channel'], 'Chan');
      final back = itemFromJson(json) as VideoItem;
      expect(back.id, 'abc');
      expect(back.channelId, 'UCx');
      expect(back.durationText, '3:07');

      const channel = ChannelItem(id: 'UCy', name: 'Other', avatar: 'a.jpg');
      expect((itemFromJson(itemToJson(channel)) as ChannelItem).name, 'Other');
      const playlist = PlaylistItem(id: 'PL1', title: 'List', countText: '16 videos');
      expect((itemFromJson(itemToJson(playlist)) as PlaylistItem).countText, '16 videos');
    });

    test('history entries keep progress', () {
      final e = HistoryEntry(const VideoItem(id: 'v', title: 't'), 120, 600, 1);
      final back = HistoryEntry.fromJson(e.toJson())!;
      expect(back.progress, closeTo(0.2, 1e-9));
      expect(HistoryEntry.fromJson({'video': 'nope'}), isNull);
    });
  });

  group('captions', () {
    const vtt = '''WEBVTT
Kind: captions
Language: en

00:00:00.199 --> 00:00:02.510 align:start position:0%
hi<00:00:00.439><c> everyone</c>

00:00:02.510 --> 00:00:02.520 align:start position:0%
hi everyone

00:00:02.520 --> 00:00:05.000 align:start position:0%
hi everyone
so &amp; on
''';

    test('parses cues, strips tags and drops the 10 ms repeats', () {
      final cues = Captions.parseVtt(vtt);
      expect(cues, hasLength(2));
      expect(cues.first.text, 'hi everyone');
      expect(cues.last.text, 'hi everyone\nso & on');
      expect(cues.last.start, const Duration(milliseconds: 2520));
    });

    test('shows the last active cue', () {
      final cues = Captions.parseVtt(vtt);
      expect(Captions.at(cues, const Duration(seconds: 1)), 'hi everyone');
      expect(Captions.at(cues, const Duration(seconds: 3)), 'hi everyone\nso & on');
      expect(Captions.at(cues, const Duration(seconds: 6)), '');
    });
  });
}

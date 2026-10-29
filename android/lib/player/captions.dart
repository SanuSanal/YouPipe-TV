import 'package:dio/dio.dart';

/// One caption cue.
class Cue {
  const Cue(this.start, this.end, this.text);

  final Duration start;
  final Duration end;
  final String text;
}

/// Captions from NewPipe's WebVTT tracks. Auto-generated tracks roll two lines, each cue repeating the line before;
/// showing the last active cue reproduces that.
abstract final class Captions {
  static final _cache = <String, List<Cue>>{};
  static final _dio = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 20)));

  static Future<List<Cue>> load(String url) async {
    final cached = _cache[url];
    if (cached != null) return cached;
    final res = await _dio.get<String>(url, options: Options(responseType: ResponseType.plain));
    return _cache[url] = parseVtt(res.data ?? '');
  }

  static final _timing = RegExp(r'^(\S+)\s+-->\s+(\S+)');
  static final _tags = RegExp(r'<[^>]*>');

  static Duration? _time(String s) {
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final secs = double.tryParse(parts.last);
    if (secs == null) return null;
    final mins = int.tryParse(parts[parts.length - 2]) ?? 0;
    final hours = parts.length > 2 ? int.tryParse(parts[parts.length - 3]) ?? 0 : 0;
    return Duration(milliseconds: ((hours * 3600 + mins * 60) * 1000 + secs * 1000).round());
  }

  static List<Cue> parseVtt(String vtt) {
    final out = <Cue>[];
    final lines = vtt.replaceAll('\r', '').split('\n');
    for (var i = 0; i < lines.length; i++) {
      final m = _timing.firstMatch(lines[i]);
      if (m == null) continue;
      final start = _time(m[1]!);
      final end = _time(m[2]!);
      final text = <String>[];
      while (i + 1 < lines.length && lines[i + 1].trim().isNotEmpty) {
        final t = lines[++i]
            .replaceAll(_tags, '')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .trim();
        if (t.isNotEmpty) text.add(t);
      }
      // Auto-generated tracks have 10 ms cues that only repeat the line; they'd flicker.
      if (start != null && end != null && text.isNotEmpty && end - start > const Duration(milliseconds: 50)) {
        out.add(Cue(start, end, text.join('\n')));
      }
    }
    return out;
  }

  /// The text to show at [t].
  static String at(List<Cue> cues, Duration t) {
    Cue? last;
    for (final c in cues) {
      if (c.start > t) break;
      if (t < c.end) last = c;
    }
    return last?.text ?? '';
  }
}

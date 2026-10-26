// Tries the 2 MiB offset with different request headers to see whether the
// ~1 MiB wall is tied to the client identity sent with the range request.
//
// Usage: dart run tool/probe_headers.dart [videoId]
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const _androidUa =
    'com.google.android.youtube/19.29.37 (Linux; U; Android 14; en_US) gzip';
const _desktopUa =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

final _modes = <String, void Function(HttpClientRequest)>{
  'bare': (_) {},
  'android-ua': (r) => r.headers.set(HttpHeaders.userAgentHeader, _androidUa),
  'desktop-ua-referer': (r) {
    r.headers.set(HttpHeaders.userAgentHeader, _desktopUa);
    r.headers.set(HttpHeaders.refererHeader, 'https://www.youtube.com/');
  },
  'origin': (r) {
    r.headers.set(HttpHeaders.userAgentHeader, _androidUa);
    r.headers.set('Origin', 'https://www.youtube.com');
    r.headers.set(HttpHeaders.refererHeader, 'https://www.youtube.com/');
  },
};

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final yt = YoutubeExplode();
  final client = HttpClient();
  try {
    for (final mode in _modes.entries) {
      final manifest = await yt.videos.streams.getManifest(id);
      final stream = manifest.audioOnly
          .where((s) => s.fragments.isEmpty && s.tag == 140)
          .firstWhere((s) => (s.audioTrack?.id ?? '').startsWith('en'));
      final start = 2 << 20;
      final request = await client.getUrl(stream.url);
      request.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=$start-${start + 65535}',
      );
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      mode.value(request);
      final response = await request.close();
      var read = 0;
      try {
        await for (final chunk in response) {
          read += chunk.length;
          if (read >= 65536) break;
        }
      } catch (_) {}
      stdout.writeln(
        '${mode.key} @2MiB -> ${response.statusCode}/$read '
        '${response.headers.value(HttpHeaders.contentRangeHeader)}',
      );
    }
  } finally {
    client.close(force: true);
    yt.close();
  }
}

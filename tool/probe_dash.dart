// Shows how audio tracks appear as progressive vs DASH-fragmented streams and
// whether single DASH fragments can be fetched beyond the 1 MiB progressive
// wall.
//
// Usage: dart run tool/probe_dash.dart [videoId]
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final yt = YoutubeExplode();
  final client = HttpClient();
  try {
    final manifest = await yt.videos.streams.getManifest(id);
    final audio = manifest.audioOnly.toList();
    stdout.writeln('audioOnly=${audio.length}');
    for (final s in audio) {
      stdout.writeln(
        'tag=${s.tag} ${s.audioTrack?.id} ${s.audioTrack?.displayName} '
        'c=${s.container.name} size=${s.size.totalBytes} '
        'frags=${s.fragments.length} '
        'xtags=${s.url.queryParameters['xtags']}',
      );
      if (s.fragments.isEmpty) continue;
      stdout.writeln('  base=${s.url}');
      for (final f in s.fragments.take(3)) {
        stdout.writeln('  frag=${f.path}');
      }
      final base = s.url;
      final first = s.fragments.first.path;
      final target = base.resolve(first);
      final request = await client.getUrl(target);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();
      var read = 0;
      try {
        await for (final chunk in response) {
          read += chunk.length;
          if (read > (1 << 20)) break;
        }
      } catch (_) {}
      stdout.writeln(
        '  fetch $target -> ${response.statusCode} read=$read '
        'type=${response.headers.contentType}',
      );
      break;
    }
  } finally {
    client.close(force: true);
    yt.close();
  }
}

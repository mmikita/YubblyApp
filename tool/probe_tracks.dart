// Tests byte ranges on several audio tracks of a video to see whether the
// 403 wall depends on the track (e.g. auto-dubbed audio) or the offset.
//
// Usage: dart run tool/probe_tracks.dart [videoId]
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final yt = YoutubeExplode();
  final client = HttpClient();
  try {
    final manifest = await yt.videos.streams.getManifest(id);
    final tracks = manifest.audioOnly
        .where((s) => s.fragments.isEmpty)
        .toList();
    stdout.writeln('tracks=${tracks.length}');

    Future<void> attempt(String label, Uri url, int start) async {
      final end = start + 65535;
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();
      var read = 0;
      try {
        await for (final chunk in response) {
          read += chunk.length;
          if (read >= 65536) break;
        }
      } catch (_) {}
      stdout.writeln(
        '  $label @$start: ${response.statusCode} read=$read '
        'cr=${response.headers.value(HttpHeaders.contentRangeHeader)}',
      );
    }

    final seen = <String>{};
    for (final stream in tracks) {
      final label = '${stream.audioTrack?.id}/${stream.container.name}';
      if (!seen.add(label)) continue;
      stdout.writeln(
        '$label size=${stream.size.totalBytes} '
        'xtags=${stream.url.queryParameters['xtags']} '
        'c=${stream.url.queryParameters['c']} '
        'rqh=${stream.url.queryParameters['rqh']}',
      );
      await attempt('fresh-a', stream.url, 0);
      await attempt('fresh-b', stream.url, 2 << 20);
      if (seen.length >= 6) break;
    }
  } finally {
    client.close(force: true);
    yt.close();
  }
}

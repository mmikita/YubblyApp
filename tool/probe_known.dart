// Compares the byte window on well known short and medium length videos.
//
// Usage: dart run tool/probe_known.dart
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<String> attempt(Uri url, int start, int length) async {
  final request = await _client.getUrl(url);
  request.headers.set(
    HttpHeaders.rangeHeader,
    'bytes=$start-${start + length - 1}',
  );
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  final response = await request.close();
  var read = 0;
  try {
    await for (final chunk in response) {
      read += chunk.length;
      if (read >= length) break;
    }
  } catch (_) {}
  return '${response.statusCode}/${read ~/ 1024}K';
}

Future<void> main(List<String> args) async {
  const videos = ['dQw4w9WgXcQ', 'aqz-KE-bpKQ', '9bZkp7q19f0'];
  final yt = YoutubeExplode();
  try {
    for (final id in videos) {
      try {
        final manifest = await yt.videos.streams.getManifest(id);
        final audio = manifest.audioOnly.where((s) => s.fragments.isEmpty);
        if (audio.isEmpty) {
          stdout.writeln('$id: no progressive audio');
          continue;
        }
        final stream = audio.reduce(
          (a, b) => b.bitrate.bitsPerSecond > a.bitrate.bitsPerSecond ? b : a,
        );
        stdout.writeln(
          '$id tag=${stream.tag} size=${stream.size.totalBytes} '
          'xtags=${stream.url.queryParameters['xtags']} '
          'c=${stream.url.queryParameters['c']}',
        );
        for (final offset in [512 << 10, 1 << 20, 2 << 20]) {
          stdout.writeln(
            '  @${offset ~/ 1024}K -> ${await attempt(stream.url, offset, 65536)}',
          );
        }
      } catch (error) {
        stdout.writeln('$id failed: $error');
      }
    }
  } finally {
    _client.close(force: true);
    yt.close();
  }
}

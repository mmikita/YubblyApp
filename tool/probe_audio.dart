// Compares the 1 MiB wall across codecs and audio tracks of one video.
//
// Usage: dart run tool/probe_audio.dart [videoId]
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<String> attempt(Uri url, int start, int length) async {
  final end = start + length - 1;
  final request = await _client.getUrl(url);
  request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  final response = await request.close();
  var read = 0;
  try {
    await for (final chunk in response) {
      read += chunk.length;
      if (read >= length) break;
    }
  } catch (_) {}
  return '${response.statusCode}/$read';
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streams.getManifest(id);
    final audio = manifest.audioOnly.where((s) => s.fragments.isEmpty).toList();
    final wanted = <int, String>{
      139: 'original',
      140: 'original',
      251: 'original',
    };
    for (final entry in wanted.entries) {
      final candidates = audio
          .where((s) => s.tag == entry.key)
          .where((s) => (s.audioTrack?.id ?? '').startsWith('en'))
          .toList();
      if (candidates.isEmpty) continue;
      final stream = candidates.first;
      stdout.writeln(
        'tag=${stream.tag} ${stream.audioTrack?.id} '
        'size=${stream.size.totalBytes} '
        'xtags=${stream.url.queryParameters['xtags']} '
        'rqh=${stream.url.queryParameters['rqh']}',
      );
      stdout.writeln('  @0 64K -> ${await attempt(stream.url, 0, 65536)}');
      stdout.writeln(
        '  @2MiB 64K -> ${await attempt(stream.url, 2 << 20, 65536)}',
      );
      stdout.writeln(
        '  @512KiB 64K -> ${await attempt(stream.url, 512 << 10, 65536)}',
      );
      stdout.writeln(
        '  @1MiB+128K -> ${await attempt(stream.url, (1 << 20) + 131072, 65536)}',
      );
    }
  } finally {
    _client.close(force: true);
    yt.close();
  }
}

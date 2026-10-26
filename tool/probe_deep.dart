// Deep offsets on a long, single-language video: confirms that unrestricted
// streaming still works when the video has only one audio track.
//
// Usage: dart run tool/probe_deep.dart
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
  return '${response.statusCode}/${read ~/ 1024}K '
      '${response.headers.value(HttpHeaders.contentRangeHeader)}';
}

Future<void> main(List<String> args) async {
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streams.getManifest('aqz-KE-bpKQ');
    final stream = manifest.videoOnly.firstWhere(
      (s) => s.tag == 258 || s.fragments.isEmpty,
      orElse: () => manifest.videoOnly.first,
    );
    stdout.writeln(
      'tag=${stream.tag} size=${stream.size.totalBytes} '
      'xtags=${stream.url.queryParameters['xtags']}',
    );
    for (final offset in [2 << 20, 8 << 20, 20 << 20]) {
      stdout.writeln(
        '  @${offset ~/ (1 << 20)}MiB -> ${await attempt(stream.url, offset, 65536)}',
      );
    }
  } finally {
    _client.close(force: true);
    yt.close();
  }
}

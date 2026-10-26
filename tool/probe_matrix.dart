// Probes range behaviour on a long, single-language video and on individual
// tracks of a dubbed video, to separate "long video" from "dubbed audio".
//
// Usage: dart run tool/probe_matrix.dart [searchQuery]
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<(int, int)> attempt(Uri url, int start, {bool query = false}) async {
  final end = start + 65535;
  final target = query
      ? url.replace(
          queryParameters: {...url.queryParameters, 'range': '$start-$end'},
        )
      : url;
  final request = await _client.getUrl(target);
  if (!query) {
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
  }
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  final response = await request.close();
  var read = 0;
  try {
    await for (final chunk in response) {
      read += chunk.length;
      if (read >= 65536) break;
    }
  } catch (_) {}
  return (response.statusCode, read);
}

Future<void> main(List<String> args) async {
  final query = args.isEmpty ? 'lofi hip hop radio 1 hour' : args.first;
  final yt = YoutubeExplode();
  try {
    final results = await yt.search.search(query);
    final long = results
        .where((v) => (v.duration?.inMinutes ?? 0) >= 20)
        .take(2)
        .toList();
    stdout.writeln(
      'long videos: ${long.map((v) => '${v.id}=${v.duration}').join(', ')}',
    );
    for (final video in long) {
      final manifest = await yt.videos.streams.getManifest(video.id.value);
      final stream = manifest.audioOnly
          .where((s) => s.fragments.isEmpty)
          .reduce(
            (a, b) => b.bitrate.bitsPerSecond > a.bitrate.bitsPerSecond ? b : a,
          );
      stdout.writeln(
        '${video.id} tag=${stream.tag} size=${stream.size.totalBytes} '
        'xtags=${stream.url.queryParameters['xtags']} '
        'rqh=${stream.url.queryParameters['rqh']}',
      );
      for (final start in [0, 2 << 20, 8 << 20]) {
        stdout.writeln(
          '  header@$start -> ${await attempt(stream.url, start)}',
        );
      }
      stdout.writeln(
        '  query@2MiB -> ${await attempt(stream.url, 2 << 20, query: true)}',
      );
    }
  } finally {
    _client.close(force: true);
    yt.close();
  }
}

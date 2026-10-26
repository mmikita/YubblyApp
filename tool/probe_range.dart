// Decides whether the ~1 MiB 403 wall is position-based or rate-based by
// testing a couple of offsets on freshly minted URLs with pauses between them.
//
// Usage: dart run tool/probe_range.dart [videoId]
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'dQw4w9WgXcQ' : args.first;
  final yt = YoutubeExplode();
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 15);
  try {
    final manifest = await yt.videos.streams.getManifest(id);
    final stream = manifest.audioOnly
        .where((s) => s.fragments.isEmpty)
        .reduce(
          (a, b) => b.bitrate.bitsPerSecond > a.bitrate.bitsPerSecond ? b : a,
        );
    stdout.writeln('size=${stream.size.totalBytes} tag=${stream.tag}');

    Future<Uri> fresh() async {
      final m = await yt.videos.streams.getManifest(id);
      return m.audioOnly.firstWhere((x) => x.tag == stream.tag).url;
    }

    Future<void> attempt(
      String label,
      Uri url,
      int start, {
      bool query = false,
    }) async {
      final end = start + 65535;
      final target = query
          ? url.replace(
              queryParameters: {...url.queryParameters, 'range': '$start-$end'},
            )
          : url;
      final request = await client.getUrl(target);
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
      stdout.writeln(
        '$label @$start: ${response.statusCode} read=$read '
        'cr=${response.headers.value(HttpHeaders.contentRangeHeader)}',
      );
    }

    for (final start in [0, 2 << 20, 5 << 20]) {
      await attempt('header', await fresh(), start);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    for (final start in [2 << 20]) {
      await attempt('query', await fresh(), start, query: true);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  } finally {
    client.close(force: true);
    yt.close();
  }
}

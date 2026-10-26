import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Temporary diagnostic: can a segmented (fresh URL per 1 MiB) reader stream a
// whole audio track, and how fast?
Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final segKiB = args.length > 1 ? int.parse(args[1]) : 1024;
  final clientName = args.length > 2 ? args[2] : 'default';
  final yt = YoutubeExplode();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final watch = Stopwatch()..start();
  try {
    final manifest = await yt.videos.streams
        .getManifest(id, ytClients: _clients(clientName))
        .timeout(const Duration(seconds: 60));
    final track = manifest.audioOnly
        .where((s) => s.fragments.isEmpty && s.container.name == 'mp4')
        .first;
    final total = track.size.totalBytes;
    final tag = track.tag;
    stdout.writeln(
      'track ${track.audioTrack?.id} itag=$tag total=$total '
      'throttled=${track.isThrottled} c=${track.url.queryParameters['c']} '
      '({${watch.elapsedMilliseconds}ms})',
    );

    var offset = 0;
    var segments = 0;
    var mints = 0;
    final segment = segKiB * 1024;
    while (offset < total && segments * segment < 6 * 1024 * 1024) {
      final to = (offset + segment - 1).clamp(0, total - 1);
      var attempt = 0;
      var ok = false;
      while (!ok && attempt < 4) {
        attempt++;
        mints++;
        final m = await yt.videos.streams
            .getManifest(id, ytClients: _clients(clientName))
            .timeout(const Duration(seconds: 60));
        final fresh = m.audioOnly.firstWhere((s) => s.tag == tag);
        final stopwatch = Stopwatch()..start();
        final response = await _get(client, fresh.url, offset, to);
        if (response == null) {
          stdout.writeln(
            '  [$offset] attempt $attempt failed (${stopwatch.elapsedMilliseconds}ms)',
          );
          continue;
        }
        stdout.writeln(
          '  [$offset..$to] HTTP ${response.$1} bytes=${response.$2} '
          'in ${stopwatch.elapsedMilliseconds}ms (attempt $attempt)',
        );
        ok = response.$1 == 206 && response.$2 == to - offset + 1;
      }
      if (!ok) {
        stdout.writeln('giving up at $offset');
        break;
      }
      offset = to + 1;
      segments++;
    }
    stdout.writeln(
      'read ${(offset / 1048576).toStringAsFixed(1)} MiB in '
      '${watch.elapsedMilliseconds}ms with $mints manifests',
    );
  } finally {
    client.close(force: true);
    yt.close();
  }
}

Future<(int, int)?> _get(HttpClient client, Uri url, int from, int to) async {
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-$to');
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = await response.fold<int>(0, (n, c) => n + c.length);
    return (response.statusCode, bytes);
  } catch (e) {
    stdout.writeln('    error $e');
    return null;
  }
}

List<YoutubeApiClient>? _clients(String name) {
  switch (name) {
    case 'ios':
      return [YoutubeApiClient.ios];
    case 'android':
      return [YoutubeApiClient.android];
    case 'mweb':
      return [YoutubeApiClient.mweb];
    default:
      return null;
  }
}

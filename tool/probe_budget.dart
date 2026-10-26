import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Temporary diagnostic: how much data can a single googlevideo URL serve?
Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final yt = YoutubeExplode();
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 20);
  try {
    final mint = await _timedManifest(yt, id);
    final url = mint.$2;
    stdout.writeln('mint#1 ${mint.$1}ms');

    await _probe(client, 'first 1MiB', url, 0, 1024 * 1024);
    await _probe(client, 'next 1MiB (same url)', url, 1024 * 1024, 1024 * 1024);

    final m2 = await _timedManifest(yt, id);
    final u2 = m2.$2;
    stdout.writeln('mint#2 ${m2.$1}ms');
    await _probe(client, 'mid 1MiB @5MB', u2, 5000000, 1024 * 1024);
    await _probe(
      client,
      'mid 64KiB @5MB+1MB',
      u2,
      5000000 + 1024 * 1024,
      64 * 1024,
    );

    final m3 = await _timedManifest(yt, id);
    final u3 = m3.$2;
    stdout.writeln('mint#3 ${m3.$1}ms');
    await _probe(client, 'repeat 64KiB @0', u3, 0, 64 * 1024);
    await _probe(client, 'repeat 64KiB @0 again', u3, 0, 64 * 1024);
    await _probe(client, 'repeat 64KiB @0 again 2', u3, 0, 64 * 1024);
    await _probe(client, 'jump 64KiB @3MB', u3, 3000000, 64 * 1024);
  } finally {
    client.close(force: true);
    yt.close();
  }
}

Future<(int, String)> _timedManifest(YoutubeExplode yt, String id) async {
  final watch = Stopwatch()..start();
  final manifest = await yt.videos.streams
      .getManifest(id)
      .timeout(const Duration(seconds: 60));
  final track = manifest.audioOnly
      .where((s) => s.fragments.isEmpty && s.container.name == 'mp4')
      .first;
  return (watch.elapsedMilliseconds, track.url.toString());
}

Future<void> _probe(
  HttpClient client,
  String label,
  String raw,
  int from,
  int length,
) async {
  final to = from + length - 1;
  try {
    final request = await client.getUrl(Uri.parse(raw));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-$to');
    final response = await request.close().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw StateError('timeout'),
    );
    final bytes = await response.fold<int>(0, (n, c) => n + c.length);
    stdout.writeln(
      '  $label $from-$to -> HTTP ${response.statusCode} bytes=$bytes '
      '${response.headers.value(HttpHeaders.contentRangeHeader) ?? ''}',
    );
  } catch (e) {
    stdout.writeln('  $label $from-$to -> ERROR $e');
  }
}

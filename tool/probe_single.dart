// One isolated range request per process: fresh manifest, fresh URL, single
// HTTP request. Used to measure the byte window without cross-request effects.
//
// Usage: dart run tool/probe_single.dart <offsetKiB> <lengthKiB> [videoId]
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final offset = int.parse(args[0]) * 1024;
  final length = args.length > 1 ? int.parse(args[1]) * 1024 : 65536;
  final id = args.length > 2 ? args[2] : 'zA-UHB2WcT4';
  final yt = YoutubeExplode();
  final client = HttpClient();
  try {
    final manifest = await yt.videos.streams.getManifest(id);
    final stream = manifest.audioOnly
        .where((s) => s.fragments.isEmpty && s.tag == 140)
        .firstWhere((s) => (s.audioTrack?.id ?? '').startsWith('en'));
    final request = await client.getUrl(stream.url);
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=$offset-${offset + length - 1}',
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
    stdout.writeln(
      '@${offset ~/ 1024}K len=${length ~/ 1024}K -> '
      '${response.statusCode}/$read '
      '${response.headers.value(HttpHeaders.contentRangeHeader)}',
    );
  } finally {
    client.close(force: true);
    yt.close();
  }
}

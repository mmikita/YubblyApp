// Downloads a whole audio track with a single request to check whether
// googlevideo allows one sequential download per URL.
//
// Usage: dart run tool/probe_full.dart [videoId] [tag]
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final tag = args.length > 1 ? int.parse(args[1]) : 139;
  final yt = YoutubeExplode();
  final client = HttpClient();
  final started = DateTime.now();
  try {
    for (final open in [false, true]) {
      final manifest = await yt.videos.streams.getManifest(id);
      final stream = manifest.audioOnly
          .where((s) => s.fragments.isEmpty && s.tag == tag)
          .firstWhere((s) => (s.audioTrack?.id ?? '').startsWith('en'));
      stdout.writeln('tag=$tag size=${stream.size.totalBytes} open=$open');
      final request = await client.getUrl(stream.url);
      request.headers.set(
        HttpHeaders.rangeHeader,
        open ? 'bytes=0-' : 'bytes=0-${stream.size.totalBytes - 1}',
      );
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();
      var read = 0;
      try {
        await for (final chunk in response) {
          read += chunk.length;
        }
      } catch (error) {
        stdout.writeln('  read error after $read: $error');
      }
      stdout.writeln(
        'open=$open -> ${response.statusCode} read=$read '
        'in ${DateTime.now().difference(started).inSeconds}s',
      );
      if (read == stream.size.totalBytes) break;
    }
  } finally {
    client.close(force: true);
    yt.close();
  }
}

// Checks whether the default client exposes an HLS manifest for a VOD video.
//
// Usage: dart run tool/probe_hls.dart [videoId]
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final yt = YoutubeExplode();
  final client = HttpClient();
  try {
    try {
      final url = await yt.videos.streams.getHttpLiveStreamUrl(VideoId(id));
      stdout.writeln('hls=$url');
      final response = await (await client.getUrl(Uri.parse(url))).close();
      stdout.writeln('hls fetch -> ${response.statusCode}');
      await for (final chunk in response) {
        stdout.write(String.fromCharCodes(chunk.take(600)));
        break;
      }
      stdout.writeln();
    } catch (error) {
      stdout.writeln('no hls: $error');
    }
  } finally {
    client.close(force: true);
    yt.close();
  }
}

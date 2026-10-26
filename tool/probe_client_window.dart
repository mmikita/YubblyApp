// Checks whether other YouTube clients hand out audio URLs that serve byte
// ranges past the ~1 MiB wall.
//
// Usage: dart run tool/probe_client_window.dart [videoId]
//
// Deprecated clients stay in the matrix on purpose: the probe checks whether
// they still hand out URLs that serve more than the first megabyte.
// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

final _clients = <String, YoutubeApiClient>{
  'android': YoutubeApiClient.android,
  'androidSdkless': YoutubeApiClient.androidSdkless,
  'androidMusic': YoutubeApiClient.androidMusic,
  'androidVr': YoutubeApiClient.androidVr,
  'safari': YoutubeApiClient.safari,
  'ios': YoutubeApiClient.ios,
  'tvSimplyEmbedded': YoutubeApiClient.tvSimplyEmbedded,
  'mweb': YoutubeApiClient.mweb,
};

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
  return '${response.statusCode}/${read ~/ 1024}K';
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final yt = YoutubeExplode();
  try {
    for (final entry in _clients.entries) {
      stdout.writeln('== ${entry.key}');
      try {
        final manifest = await yt.videos.streams.getManifest(
          id,
          ytClients: [entry.value],
        );
        final audio = manifest.audioOnly.where((s) => s.fragments.isEmpty);
        if (audio.isEmpty) {
          stdout.writeln('  no progressive audio');
          continue;
        }
        final stream = audio.reduce(
          (a, b) => b.bitrate.bitsPerSecond > a.bitrate.bitsPerSecond ? b : a,
        );
        final params = stream.url.queryParameters;
        stdout.writeln(
          '  tag=${stream.tag} size=${stream.size.totalBytes} '
          'c=${params['c']} rqh=${params['rqh']} '
          'ratebypass=${params['ratebypass']} '
          'xtags=${params['xtags']}',
        );
        for (final offset in [512 << 10, 2 << 20, 8 << 20]) {
          stdout.writeln(
            '  @${offset ~/ 1024}K -> '
            '${await attempt(stream.url, offset, 65536)}',
          );
        }
      } catch (error) {
        stdout.writeln('  failed: $error');
      }
    }
  } finally {
    _client.close(force: true);
    yt.close();
  }
}

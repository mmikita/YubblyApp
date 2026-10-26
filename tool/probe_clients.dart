import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Temporary diagnostic: compare player clients and byte-range requests.
Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final yt = YoutubeExplode();
  final clients = <String, YoutubeApiClient>{
    'ios': YoutubeApiClient.ios,
    'android': YoutubeApiClient.android,
    'androidSdkless': YoutubeApiClient.androidSdkless,
    'androidVr': YoutubeApiClient.androidVr,
    'tv': YoutubeApiClient.tv,
    'mweb': YoutubeApiClient.mweb,
  };
  try {
    for (final entry in clients.entries) {
      stdout.writeln('\n=== ${entry.key} ===');
      try {
        final manifest = await yt.videos.streams
            .getManifest(id, ytClients: [entry.value])
            .timeout(const Duration(seconds: 45));
        final audio = manifest.audioOnly
            .where((s) => s.fragments.isEmpty && s.container.name == 'mp4')
            .toList();
        stdout.writeln('audio mp4: ${audio.length}');
        for (final s in audio.take(20)) {
          stdout.writeln(
            '  ${s.audioTrack?.id} ${s.audioTrack?.displayName} '
            '${s.size.totalBytes} c=${s.url.queryParameters['c']} '
            'gir=${s.url.queryParameters['gir']} '
            'rqh=${s.url.queryParameters['rqh']} '
            'range=${s.url.queryParameters['range']}',
          );
        }
        if (audio.isEmpty) continue;
        final sample = audio.first;
        await _test('header', sample.url, header: true);
        await _test('query', sample.url, header: false);
      } catch (e) {
        stdout.writeln('FAILED: $e');
      }
    }
  } finally {
    yt.close();
  }
}

Future<void> _test(String label, Uri base, {required bool header}) async {
  final client = HttpClient();
  try {
    const from = 40000000;
    const to = 40004095;
    final url = header
        ? base
        : base.replace(
            queryParameters: {...base.queryParameters, 'range': '$from-$to'},
          );
    final request = await client.getUrl(url);
    if (header) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-$to');
    }
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
    );
    final response = await request.close().timeout(const Duration(seconds: 20));
    final bytes = await response.fold<int>(0, (n, c) => n + c.length);
    stdout.writeln(
      '  $label: HTTP ${response.statusCode} bytes=$bytes '
      '${response.headers.value(HttpHeaders.contentRangeHeader)}',
    );
  } catch (e) {
    stdout.writeln('  $label: ERROR $e');
  } finally {
    client.close(force: true);
  }
}

// Compares audio URL query params between the android and androidSdkless
// clients and probes a deep offset on the dubbed 140 track of each.
//
// Usage: dart run tool/probe_android.dart [videoId]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<Map<String, dynamic>> player(String id, YoutubeApiClient c) async {
  final request = await _client.postUrl(Uri.parse(c.apiUrl));
  request.headers.contentType = ContentType.json;
  for (final entry in c.headers.entries) {
    request.headers.set(entry.key, entry.value);
  }
  request.add(
    utf8.encode(
      jsonEncode({
        'context': c.payload['context'],
        'videoId': id,
        'contentCheckOk': true,
        'racyCheckOk': true,
      }),
    ),
  );
  return jsonDecode(await utf8.decodeStream(await request.close()))
      as Map<String, dynamic>;
}

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
  return '${response.statusCode}/$read';
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  try {
    for (final entry in {
      'android': YoutubeApiClient.android,
      'androidSdkless': YoutubeApiClient.androidSdkless,
    }.entries) {
      final json = await player(id, entry.value);
      final data = json['streamingData'] as Map<String, dynamic>? ?? {};
      final formats =
          (data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final audio = formats.where(
        (f) => '${f['mimeType']}'.startsWith('audio/mp4'),
      );
      stdout.writeln('== ${entry.key} audio/mp4=${audio.length}');
      for (final format in audio) {
        final url = Uri.parse(format['url'] as String);
        final p = url.queryParameters;
        stdout.writeln(
          '  itag=${format['itag']} br=${format['bitrate']} '
          'xtags=${p['xtags']} rqh=${p['rqh']} '
          'ratebypass=${p['ratebypass']} sparams=${p['sparams']}',
        );
      }
      final dubbed = audio.firstWhere(
        (f) => ((Uri.parse(f['url'] as String).queryParameters['xtags']) ?? '')
            .contains('dubbed'),
        orElse: () => audio.first,
      );
      final url = Uri.parse(dubbed['url'] as String);
      stdout.writeln(
        '  deep itag=${dubbed['itag']} '
        '@2MiB -> ${await attempt(url, 2 << 20, 65536)} '
        '@0 -> ${await attempt(url, 0, 65536)}',
      );
    }
  } finally {
    _client.close(force: true);
  }
}

// Two point check: a plain video at a deep offset vs a dubbed video at offset
// zero. Used to tell an IP wide quota apart from a per video (multi audio) gate.
//
// Usage: dart run tool/probe_gate.dart
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<Map<String, dynamic>> player(String id) async {
  final c = YoutubeApiClient.androidSdkless;
  final request = await _client.postUrl(Uri.parse(c.apiUrl));
  request.headers.contentType = ContentType.json;
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
  final response = await request.close();
  return jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
}

Future<void> probe(String label, Uri url, int start, int length) async {
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
  stdout.writeln(
    '$label @${start ~/ 1024}K -> ${response.statusCode}/$read '
    '${response.headers.value(HttpHeaders.contentRangeHeader)}',
  );
}

Future<void> main(List<String> args) async {
  try {
    // 1. Plain video, deep offset.
    final plain = await player('aqz-KE-bpKQ');
    final plainFormats =
        ((plain['streamingData'] as Map<String, dynamic>)['adaptiveFormats']
                as List)
            .cast<Map<String, dynamic>>();
    final plainAudio = plainFormats.firstWhere(
      (f) => '${f['mimeType']}'.startsWith('audio/mp4'),
    );
    stdout.writeln('aqz size=${plainAudio['contentLength']}');
    final plainUrl = Uri.parse(plainAudio['url'] as String);
    await probe('aqz', plainUrl, 8 << 20, 65536);
    await probe('aqz', plainUrl, 12 << 20, 65536);

    // 2. Dubbed video, zero offset and just past 1 MiB.
    final dubbed = await player('VnwNR5qR9ow');
    final dubbedFormats =
        ((dubbed['streamingData'] as Map<String, dynamic>)['adaptiveFormats']
                as List)
            .cast<Map<String, dynamic>>();
    final track = dubbedFormats.firstWhere(
      (f) =>
          '${f['mimeType']}'.startsWith('audio/') &&
          (Uri.parse(f['url'] as String).queryParameters['xtags'] ?? '')
              .contains('dubbed'),
    );
    stdout.writeln(
      'VnwNR5qR9ow size=${track['contentLength']} '
      'xtags=${Uri.parse(track['url'] as String).queryParameters['xtags']}',
    );
    final trackUrl = Uri.parse(track['url'] as String);
    await probe('dubbed', trackUrl, 0, 65536);
    await probe('dubbed', trackUrl, 900 << 10, 65536);
    await probe('dubbed', trackUrl, (1 << 20) - 65536, 65536);
  } finally {
    _client.close(force: true);
  }
}

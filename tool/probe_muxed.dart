// Checks the muxed stream of a multi audio video: does it carry xtags and can
// it be read past 1 MiB?
//
// Usage: dart run tool/probe_muxed.dart [videoId]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

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
  return '${response.statusCode}/${read ~/ 1024}K '
      '${response.headers.value(HttpHeaders.contentRangeHeader)}';
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  try {
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
    final json =
        jsonDecode(await utf8.decodeStream(await request.close()))
            as Map<String, dynamic>;
    final data = json['streamingData'] as Map<String, dynamic>? ?? {};
    for (final raw in (data['formats'] as List?) ?? const []) {
      final format = raw as Map<String, dynamic>;
      final url = Uri.parse(format['url'] as String);
      final params = url.queryParameters;
      stdout.writeln(
        'itag=${format['itag']} len=${format['contentLength']} '
        'xtags=${params['xtags']} rqh=${params['rqh']} '
        'ratebypass=${params['ratebypass']}',
      );
      for (final offset in [0, 2 << 20]) {
        stdout.writeln(
          '  @${offset ~/ (1 << 20)}MiB -> ${await attempt(url, offset, 65536)}',
        );
      }
    }
  } finally {
    _client.close(force: true);
  }
}

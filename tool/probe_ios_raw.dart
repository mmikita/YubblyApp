// Extracts `ios` client URLs straight from the player response and probes the
// `range=` query form at increasing offsets.
//
// Usage: dart run tool/probe_ios_raw.dart [videoId] [itag]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<Map<String, dynamic>> player(YoutubeApiClient c, String id) async {
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
  final body = await utf8.decodeStream(response);
  return jsonDecode(body) as Map<String, dynamic>;
}

Future<void> probe(String label, Uri url, int start, int length) async {
  final target = url.replace(
    queryParameters: {
      ...url.queryParameters,
      'range': '$start-${start + length - 1}',
    },
  );
  final request = await _client.getUrl(target);
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
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final itag = args.length > 1 ? args[1] : '140';
  try {
    final json = await player(YoutubeApiClient.ios, id);
    final data = json['streamingData'] as Map<String, dynamic>? ?? {};
    final formats = [
      ...?(data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>(),
      ...?(data['formats'] as List?)?.cast<Map<String, dynamic>>(),
    ];
    final stream = formats.firstWhere(
      (f) => '${f['itag']}' == itag,
      orElse: () => const {},
    );
    if (stream.isEmpty) {
      stdout.writeln(
        'no itag $itag; available: ${formats.map((f) => f['itag'])}',
      );
      return;
    }
    final url = Uri.parse(stream['url'] as String);
    stdout.writeln(
      'itag=$itag len=${stream['contentLength']} c=${url.queryParameters['c']} '
      'rqh=${url.queryParameters['rqh']} '
      'xtags=${url.queryParameters['xtags']}',
    );
    const size = 65536;
    for (final offset in [0, 512 << 10, 1 << 20, 2 << 20, 10 << 20]) {
      await probe('query', url, offset, size);
    }
  } finally {
    _client.close(force: true);
  }
}

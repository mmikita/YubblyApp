// Tests whether appending `&sq=N` (segment number, unsigned) to an audio URL
// makes googlevideo return that DASH segment instead of a byte range.
//
// Usage: dart run tool/probe_sq.dart [videoId]
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
  return jsonDecode(await utf8.decodeStream(await request.close()))
      as Map<String, dynamic>;
}

Future<String> probe(String label, Uri url, {int cap = 1 << 20}) async {
  final request = await _client.getUrl(url);
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  final response = await request.close();
  final bytes = <int>[];
  try {
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length >= cap) break;
    }
  } catch (_) {}
  final head = base64Encode(bytes.take(12).toList());
  return '$label -> ${response.statusCode}/${bytes.length}B head=$head '
      'len=${response.headers.value(HttpHeaders.contentLengthHeader)}';
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  try {
    final json = await player(id);
    final data = json['streamingData'] as Map<String, dynamic>? ?? {};
    final formats =
        (data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    final format = formats.firstWhere(
      (f) =>
          '${f['itag']}' == '140' &&
          (Uri.parse(f['url'] as String).queryParameters['xtags'] ?? '')
              .contains('dubbed'),
    );
    final url = Uri.parse(format['url'] as String);
    stdout.writeln('len=${format['contentLength']}');
    stdout.writeln(await probe('plain', url, cap: 200 << 10));
    for (final sq in [0, 1, 2, 10, 100]) {
      final withSq = url.replace(
        queryParameters: {...url.queryParameters, 'sq': '$sq'},
      );
      stdout.writeln(await probe('sq=$sq', withSq));
    }
  } finally {
    _client.close(force: true);
  }
}

// Verifies whether the `range=` query really shifts the returned bytes on an
// `ios` URL of a multi audio video, by comparing chunk digests.
//
// Usage: dart run tool/probe_ios_digest.dart [videoId]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<String> fetch(Uri url, String range) async {
  final target = url.replace(
    queryParameters: {...url.queryParameters, 'range': range},
  );
  final request = await _client.getUrl(target);
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  final response = await request.close();
  final bytes = <int>[];
  try {
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length >= 65536) break;
    }
  } catch (_) {}
  final digest = base64Encode(bytes.take(16).toList());
  return '${response.statusCode}/${bytes.length} head=$digest';
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  try {
    final c = YoutubeApiClient.ios;
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
    final formats =
        (data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    final stream = formats.firstWhere(
      (f) => '${f['mimeType']}'.startsWith('audio/') && '${f['itag']}' == '140',
      orElse: () =>
          formats.firstWhere((f) => '${f['mimeType']}'.startsWith('audio/')),
    );
    final url = Uri.parse(stream['url'] as String);
    stdout.writeln('itag=${stream['itag']} len=${stream['contentLength']}');
    for (final range in [
      '0-65535',
      '524288-589823',
      '900000-965535',
      '1048576-1114111',
      '2097152-2162687',
    ]) {
      stdout.writeln('  $range -> ${await fetch(url, range)}');
    }
  } finally {
    _client.close(force: true);
  }
}

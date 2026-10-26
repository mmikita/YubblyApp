// Asks one question: does a *virgin* media URL serve a range that starts past
// the first megabyte? Each request below uses a URL that has never been used.
//
// Usage: dart run tool/probe_offset_fresh.dart [videoId]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<Uri> audioUrl(String id) async {
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
  final formats =
      (data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>() ??
      const [];
  return Uri.parse(
    formats.firstWhere(
          (f) =>
              '${f['itag']}' == '140' &&
              (Uri.parse(f['url'] as String).queryParameters['xtags'] ?? '')
                  .contains('dubbed'),
        )['url']
        as String,
  );
}

Future<String> step(Uri url, int start, int length) async {
  final request = await _client.getUrl(url)
    ..headers.set(
      HttpHeaders.rangeHeader,
      'bytes=$start-${start + length - 1}',
    );
  final response = await request.close().timeout(
    const Duration(seconds: 15),
    onTimeout: () => throw StateError('timeout'),
  );
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
  const size = 64 << 10;
  final offsets = <int>[0, 1 << 20, 1 << 21, (1.5 * (1 << 20)).round()];
  try {
    for (final offset in offsets) {
      final url = await audioUrl(id);
      String result;
      try {
        result = await step(url, offset, size);
      } catch (error) {
        result = 'error $error';
      }
      stdout.writeln(
        'fresh url @${(offset / (1 << 20)).toStringAsFixed(2)}M -> $result',
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  } finally {
    _client.close(force: true);
  }
}

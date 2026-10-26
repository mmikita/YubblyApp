// Tries appending unsigned query parameters (ratebypass, gir, ...) to an
// audio-only URL of a multi audio video to lift the 1 MiB range cap.
//
// Usage: dart run tool/probe_params.dart [videoId]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<String> attempt(String label, Uri url, int start, int length) async {
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
  return '$label -> ${response.statusCode}/$read '
      '${response.headers.value(HttpHeaders.contentRangeHeader)}';
}

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
  final stream = formats.firstWhere(
    (f) => '${f['itag']}' == '140',
    orElse: () =>
        formats.firstWhere((f) => '${f['mimeType']}'.startsWith('audio/')),
  );
  return Uri.parse(stream['url'] as String);
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  const deep = 4 << 20;
  try {
    final url = await audioUrl(id);
    stdout.writeln('base xtags=${url.queryParameters['xtags']}');
    stdout.writeln(await attempt('bare', url, deep, 65536));
    stdout.writeln(
      await attempt(
        'ratebypass=yes',
        url.replace(
          queryParameters: {...url.queryParameters, 'ratebypass': 'yes'},
        ),
        deep,
        65536,
      ),
    );
    stdout.writeln(
      await attempt(
        'ratebypass=yes+gir',
        url.replace(
          queryParameters: {
            ...url.queryParameters,
            'ratebypass': 'yes',
            'gir': 'yes',
          },
        ),
        deep,
        65536,
      ),
    );
    stdout.writeln(
      await attempt(
        'rn=1',
        url.replace(queryParameters: {...url.queryParameters, 'rn': '1'}),
        deep,
        65536,
      ),
    );
    stdout.writeln(
      await attempt(
        'rn=1+rbuf=0',
        url.replace(
          queryParameters: {...url.queryParameters, 'rn': '1', 'rbuf': '0'},
        ),
        deep,
        65536,
      ),
    );
  } finally {
    _client.close(force: true);
  }
}

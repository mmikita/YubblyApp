// Downloads a whole track with a plain GET (no Range header) to check whether
// a single sequential connection is allowed to transfer the entire file.
//
// Usage: dart run tool/probe_plain.dart [videoId] [itag]
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
  return jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final itag = args.length > 1 ? args[1] : '139';
  final clients = <String, YoutubeApiClient>{
    'androidSdkless': YoutubeApiClient.androidSdkless,
    'ios': YoutubeApiClient.ios,
  };
  try {
    for (final entry in clients.entries) {
      final json = await player(entry.value, id);
      final data = json['streamingData'] as Map<String, dynamic>? ?? {};
      final formats = [
        ...?(data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>(),
      ];
      final stream = formats.firstWhere(
        (f) => '${f['itag']}' == itag,
        orElse: () => const {},
      );
      if (stream.isEmpty) {
        stdout.writeln('${entry.key}: no itag $itag');
        continue;
      }
      final url = Uri.parse(stream['url'] as String);
      final expected = int.tryParse('${stream['contentLength']}') ?? 0;
      final started = DateTime.now();
      final request = await _client.getUrl(url);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();
      var read = 0;
      String? error;
      try {
        await for (final chunk in response) {
          read += chunk.length;
        }
      } catch (e) {
        error = '$e';
      }
      final secs = DateTime.now().difference(started).inMilliseconds / 1000;
      stdout.writeln(
        '${entry.key} itag=$itag -> ${response.statusCode} read=$read/$expected '
        'in ${secs.toStringAsFixed(1)}s $error',
      );
    }
  } finally {
    _client.close(force: true);
  }
}

// Reads a whole track in a single connection using the `ios` client
// `range=0-<end>` query form, which is not subject to the header cap.
//
// Usage: dart run tool/probe_ios_full.dart [videoId] [maxMiB]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<Map<String, dynamic>> player(String id) async {
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
  final response = await request.close();
  return jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'VnwNR5qR9ow' : args.first;
  final cap = (args.length > 1 ? int.parse(args[1]) : 8) << 20;
  try {
    final json = await player(id);
    final data = json['streamingData'] as Map<String, dynamic>? ?? {};
    final formats =
        (data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    final audio = formats
        .where((f) => '${f['mimeType']}'.startsWith('audio/mp4'))
        .toList();
    if (audio.isEmpty) {
      stdout.writeln('no audio/mp4');
      return;
    }
    final stream = audio.reduce(
      (a, b) =>
          (int.tryParse('${a['bitrate']}') ?? 0) >
              (int.tryParse('${b['bitrate']}') ?? 0)
          ? a
          : b,
    );
    final url = Uri.parse(stream['url'] as String);
    final expected = int.tryParse('${stream['contentLength']}') ?? 0;
    final target = url.replace(
      queryParameters: {
        ...url.queryParameters,
        'range': args.length > 2 ? args[2] : '0-${expected - 1}',
      },
    );
    stdout.writeln('itag=${stream['itag']} len=$expected');
    final started = DateTime.now();
    final response = await (await _client.getUrl(target)).close();
    stdout.writeln('status=${response.statusCode}');
    var read = 0;
    var capped = false;
    try {
      await for (final chunk in response) {
        read += chunk.length;
        if (read >= cap) {
          capped = true;
          break;
        }
      }
    } catch (error) {
      stdout.writeln('stream error after $read: $error');
    }
    final secs = DateTime.now().difference(started).inMilliseconds / 1000;
    stdout.writeln(
      'read=$read/$expected in ${secs.toStringAsFixed(1)}s capped=$capped',
    );
  } finally {
    _client.close(force: true);
  }
}

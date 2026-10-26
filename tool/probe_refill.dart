// Checks whether the 1 MiB window refills over time: mint a URL, wait, then ask
// for a deep offset.
//
// Usage: dart run tool/probe_refill.dart [videoId] [waitSeconds]
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

Future<String> probe(Uri url, int start, int length) async {
  final request = await _client.getUrl(url);
  request.headers.set(
    HttpHeaders.rangeHeader,
    'bytes=$start-${start + length - 1}',
  );
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
  final wait = args.length > 1 ? int.parse(args[1]) : 20;
  try {
    final early = await audioUrl(id);
    stdout.writeln('minted');
    await Future<void>.delayed(const Duration(seconds: 30 * 0 + 0));
    stdout.writeln('early @512K -> ${await probe(early, 512 << 10, 65536)}');
    stdout.writeln(
      'early @1.5M -> ${await probe(early, (3 << 19) + (1 << 20), 65536)}',
    );
    await Future<void>.delayed(Duration(seconds: wait));
    stdout.writeln('late  @2M   -> ${await probe(early, 2 << 20, 65536)}');
    final fresh = await audioUrl(id);
    stdout.writeln('fresh @2M   -> ${await probe(fresh, 2 << 20, 65536)}');
  } finally {
    _client.close(force: true);
  }
}

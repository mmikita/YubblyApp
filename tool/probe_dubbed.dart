// Finds an auto-dubbed (multi audio track) video via search and measures its
// byte window, comparing a dubbed track with the original one.
//
// Usage: dart run tool/probe_dubbed.dart [query]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();
const _ua =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

Future<String> get(String url, {bool desktop = false}) async {
  final request = await _client.getUrl(Uri.parse(url));
  if (desktop) request.headers.set(HttpHeaders.userAgentHeader, _ua);
  final response = await request.close();
  return utf8.decodeStream(response);
}

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
    '  $label @${start ~/ 1024}K -> ${response.statusCode}/$read '
    '${response.headers.value(HttpHeaders.contentRangeHeader)}',
  );
}

Future<void> main(List<String> args) async {
  final query = args.isEmpty ? 'jak gotować' : args.first;
  try {
    final html = await get(
      'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(query)}'
      '&sp=EgIYAw%253D%253D',
      desktop: true,
    );
    final ids = RegExp(
      r'"videoId":"([\w-]{11})"',
    ).allMatches(html).map((m) => m.group(1)!).toSet().take(8).toList();
    stdout.writeln('candidates=${ids.length}');
    for (final id in ids) {
      try {
        final json = await player(id);
        final data = json['streamingData'] as Map<String, dynamic>? ?? {};
        final formats =
            (data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        String? xtagsOf(Map<String, dynamic> f) {
          final url = f['url'] as String?;
          if (url == null) return null;
          return Uri.parse(url).queryParameters['xtags'];
        }

        final audio = formats.where(
          (f) => '${f['mimeType']}'.startsWith('audio'),
        );
        final dubbed = audio
            .where((f) => (xtagsOf(f) ?? '').contains('dubbed'))
            .toList();
        final original = audio
            .where((f) => (xtagsOf(f) ?? '').contains('acont=original'))
            .toList();
        final details = json['videoDetails'] as Map<String, dynamic>? ?? {};
        stdout.writeln(
          '$id dubbed=${dubbed.length} original=${original.length} '
          'len=${details['lengthSeconds']}s',
        );
        if (dubbed.isEmpty || original.isEmpty) continue;
        final d = dubbed.first;
        final o = original.first;
        stdout.writeln(
          '  dubbed itag=${d['itag']} len=${d['contentLength']} '
          'xtags=${xtagsOf(d)}',
        );
        for (final offset in [512 << 10, 2 << 20, 4 << 20]) {
          await probe('dubbed', Uri.parse(d['url'] as String), offset, 65536);
        }
        for (final offset in [512 << 10, 2 << 20]) {
          await probe('original', Uri.parse(o['url'] as String), offset, 65536);
        }
        break;
      } catch (error) {
        stdout.writeln('$id failed: $error');
      }
    }
  } finally {
    _client.close(force: true);
  }
}

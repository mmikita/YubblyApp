// Tries the ANDROID_VR client with a matching User-Agent. That client is known
// to work without a PO token, so it may lift the ~1 MiB range cap.
//
// Usage: dart run tool/probe_vr.dart [videoId]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();
const _ua =
    'com.google.android.apps.youtube.vr.oculus/1.56.21 '
    '(Linux; U; Android 12; GB) gzip';

Future<Map<String, dynamic>> player(String id) async {
  final c = YoutubeApiClient.androidVr;
  final request = await _client.postUrl(Uri.parse(c.apiUrl));
  request.headers.contentType = ContentType.json;
  request.headers.set(HttpHeaders.userAgentHeader, _ua);
  request.headers.set('X-Goog-Api-Format-Version', '2');
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
  if (response.statusCode != 200) {
    throw StateError('HTTP ${response.statusCode}: $body');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

Future<void> probe(String label, Uri url, int start, int length) async {
  final request = await _client.getUrl(url);
  request.headers.set(
    HttpHeaders.rangeHeader,
    'bytes=$start-${start + length - 1}',
  );
  request.headers.set(HttpHeaders.userAgentHeader, _ua);
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
  final id = args.isEmpty ? 'VnwNR5qR9ow' : args.first;
  try {
    final json = await player(id);
    final status = json['playabilityStatus'] as Map<String, dynamic>?;
    stdout.writeln('status=${status?['status']} reason=${status?['reason']}');
    final data = json['streamingData'] as Map<String, dynamic>? ?? {};
    final formats = [
      ...?(data['formats'] as List?)?.cast<Map<String, dynamic>>(),
      ...?(data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>(),
    ];
    stdout.writeln('formats=${formats.length} dash=${data['dashManifestUrl']}');
    String? xtags(Map<String, dynamic> f) {
      final url = f['url'] as String?;
      return url == null ? null : Uri.parse(url).queryParameters['xtags'];
    }

    final audio = formats.where((f) => '${f['mimeType']}'.startsWith('audio'));
    final dubbed = audio
        .where((f) => (xtags(f) ?? '').contains('dubbed'))
        .toList();
    final original = audio
        .where((f) => (xtags(f) ?? '').contains('original'))
        .toList();
    stdout.writeln('dubbed=${dubbed.length} original=${original.length}');
    for (final entry in {'dubbed': dubbed, 'original': original}.entries) {
      final first = entry.value.firstOrNull;
      if (first == null) continue;
      final url = Uri.parse(first['url'] as String);
      stdout.writeln(
        '${entry.key} itag=${first['itag']} len=${first['contentLength']} '
        'xtags=${xtags(first)} c=${url.queryParameters['c']} '
        'ratebypass=${url.queryParameters['ratebypass']}',
      );
      for (final offset in [0, 512 << 10, 2 << 20]) {
        await probe(entry.key, url, offset, 65536);
      }
    }
  } catch (error) {
    stdout.writeln('failed: $error');
  } finally {
    _client.close(force: true);
  }
}

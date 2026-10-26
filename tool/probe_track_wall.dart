// Lists every audio format of a video and probes two offsets on each, using a
// *fresh* player response per request. Answers: which tracks are usable past
// the first megabyte?
//
// Usage: dart run tool/probe_track_wall.dart [videoId]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<List<Map<String, dynamic>>> formats(String id) async {
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
  return ((json['streamingData']?['adaptiveFormats'] as List?) ?? const [])
      .cast<Map<String, dynamic>>();
}

Future<String> probe(String id, int itag, int start) async {
  const length = 64 << 10;
  final fresh = (await formats(
    id,
  )).firstWhere((f) => '${f['itag']}' == '$itag', orElse: () => const {});
  final raw = fresh['url'] as String?;
  if (raw == null) return 'no url';
  final request = await _client.getUrl(Uri.parse(raw))
    ..headers.set(
      HttpHeaders.rangeHeader,
      'bytes=$start-${start + length - 1}',
    );
  try {
    final response = await request.close().timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw StateError('timeout'),
    );
    var read = 0;
    await for (final chunk in response) {
      read += chunk.length;
      if (read >= length) break;
    }
    return '${response.statusCode}/$read';
  } catch (error) {
    return 'error $error';
  }
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  try {
    for (final f in await formats(id)) {
      final mime = f['mimeType'] as String? ?? '';
      if (!mime.startsWith('audio/')) continue;
      final itag = f['itag'];
      final xtags =
          Uri.tryParse(f['url'] as String? ?? '')?.queryParameters['xtags'] ??
          '(none)';
      stdout.writeln(
        'itag $itag $mime xtags=$xtags size=${f['contentLength']}',
      );
      stdout.writeln('  @0   -> ${await probe(id, itag as int, 0)}');
      stdout.writeln('  @2M  -> ${await probe(id, itag, 2 << 20)}');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  } finally {
    _client.close(force: true);
  }
}

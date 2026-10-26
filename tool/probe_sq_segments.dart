// Dumps the raw metadata of the audio formats of a video and, when the format
// carries a segment index, downloads the DASH index and a few `&sq=` segments.
//
// Usage: dart run tool/probe_sq_segments.dart [videoId] [itag]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

Future<List<int>> read(Uri url, {String? range}) async {
  final request = await _client.getUrl(url);
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
  final response = await request.close().timeout(
    const Duration(seconds: 15),
    onTimeout: () => throw StateError('timeout'),
  );
  stdout.writeln('  GET range=$range -> ${response.statusCode}');
  final builder = BytesBuilder();
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final itag = args.length > 1 ? args[1] : '140';
  try {
    final list = await formats(id);
    final target = list.firstWhere(
      (f) => '${f['itag']}' == itag,
      orElse: () => const {},
    );
    stdout.writeln('keys=${target.keys.toList()}');
    stdout.writeln(
      'initRange=${target['initRange']} indexRange=${target['indexRange']} '
      'contentLength=${target['contentLength']}',
    );
    stdout.writeln('xtags=${target['xtags'] ?? 'none'}');
    final raw = target['url'] as String?;
    if (raw == null) return;
    final url = Uri.parse(raw);
    final initRange = target['initRange'] as Map<String, dynamic>?;
    final indexRange = target['indexRange'] as Map<String, dynamic>?;
    if (initRange != null) {
      await read(url, range: 'bytes=${initRange['start']}-${initRange['end']}');
    }
    if (indexRange != null) {
      final index = await read(
        url,
        range: 'bytes=${indexRange['start']}-${indexRange['end']}',
      );
      stdout.writeln('  index bytes=${index.length}');
    }
    for (final sq in [0, 1, 40, 200]) {
      final segment = url.replace(
        queryParameters: {...url.queryParameters, 'sq': '$sq'},
      );
      final bytes = await read(segment);
      stdout.writeln('  sq=$sq bytes=${bytes.length}');
    }
  } catch (error) {
    stdout.writeln('failed: $error');
  } finally {
    _client.close(force: true);
  }
}

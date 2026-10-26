// Checks whether the 403 wall follows the `xtags` query parameter: probes a
// gated audio URL with and without `xtags`, and a working muxed URL with a
// synthetically added `xtags`.
//
// Usage: dart run tool/probe_xtags.dart [videoId]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

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
  return jsonDecode(await utf8.decodeStream(await request.close()))
      as Map<String, dynamic>;
}

Future<String> probe(String label, String raw, int start) async {
  const length = 64 << 10;
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
    return '$label -> ${response.statusCode}/$read';
  } catch (error) {
    return '$label -> error $error';
  }
}

String without(String raw, String key) {
  final uri = Uri.parse(raw);
  final params = Map<String, String>.from(uri.queryParameters)..remove(key);
  return uri.replace(queryParameters: params).toString();
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  const deep = 4 << 20;
  try {
    final json = await player(id);
    final data = json['streamingData'] as Map<String, dynamic>? ?? const {};
    final formats =
        (data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    final muxed =
        (data['formats'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final audio = formats.firstWhere((f) => '${f['itag']}' == '140');
    final progressive = muxed.first;
    final audioUrl = audio['url'] as String;
    final muxedUrl = progressive['url'] as String;
    stdout.writeln(
      'audio xtags=${Uri.parse(audioUrl).queryParameters['xtags']}',
    );
    stdout.writeln(await probe('audio as-is', audioUrl, deep));
    stdout.writeln(
      await probe('audio no-xtags', without(audioUrl, 'xtags'), deep),
    );
    stdout.writeln(await probe('muxed as-is', muxedUrl, deep));
    final withTags = Uri.parse(muxedUrl)
        .replace(
          queryParameters: {
            ...Uri.parse(muxedUrl).queryParameters,
            'xtags': 'acont=original:lang=en-US',
          },
        )
        .toString();
    stdout.writeln(await probe('muxed +xtags', withTags, deep));
  } catch (error) {
    stdout.writeln('failed: $error');
  } finally {
    _client.close(force: true);
  }
}

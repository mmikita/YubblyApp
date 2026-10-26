// Compares the progressive (muxed) stream and the best adaptive audio of two
// videos, at offset zero and past the first megabyte, on fresh URLs.
//
// Usage: dart run tool/probe_compare.dart [videoId ...]
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
  final json =
      jsonDecode(await utf8.decodeStream(await request.close()))
          as Map<String, dynamic>;
  return json['streamingData'] as Map<String, dynamic>? ?? const {};
}

Future<String> probe(String url, int start) async {
  const length = 64 << 10;
  final request = await _client.getUrl(Uri.parse(url))
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
  final ids = args.isEmpty ? ['zA-UHB2WcT4', 'dQw4w9WgXcQ'] : args;
  try {
    for (final id in ids) {
      final data = await player(id);
      final progressive =
          (data['formats'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final adaptive =
          (data['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final muxed = progressive.isEmpty ? null : progressive.first;
      final audio = adaptive.firstWhere(
        (f) => f['itag'].toString() == '140',
        orElse: () => adaptive.isEmpty ? const {} : adaptive.first,
      );
      stdout.writeln(id);
      if (muxed?['url'] is String) {
        final url = muxed!['url'] as String;
        stdout.writeln(
          '  muxed itag ${muxed['itag']} '
          '${muxed['contentLength']} @0 -> ${await probe(url, 0)} '
          '@2M -> ${await probe(url, 2 << 20)}',
        );
      } else {
        stdout.writeln('  muxed: none');
      }
      if (audio['url'] is String) {
        final url = audio['url'] as String;
        stdout.writeln(
          '  audio itag ${audio['itag']} '
          '${audio['contentLength']} @0 -> ${await probe(url, 0)} '
          '@2M -> ${await probe(url, 2 << 20)}',
        );
      } else {
        stdout.writeln('  audio: none');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  } finally {
    _client.close(force: true);
  }
}

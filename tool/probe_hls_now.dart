// Inspects the HLS master playlist from the safari client for a multi audio
// video, then downloads the first and a late segment of an audio rendition.
//
// Usage: dart run tool/probe_hls_now.dart [videoId]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<Map<String, dynamic>> player(String id, YoutubeApiClient c) async {
  final request = await _client.postUrl(Uri.parse(c.apiUrl));
  request.headers.contentType = ContentType.json;
  for (final entry in c.headers.entries) {
    request.headers.set(entry.key, entry.value);
  }
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
    throw StateError('HTTP ${response.statusCode}: ${body.substring(0, 200)}');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

Future<String> getText(Uri url) async {
  final request = await _client.getUrl(url);
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  final response = await request.close();
  final body = await utf8.decodeStream(response);
  stdout.writeln('GET ${url.path} -> ${response.statusCode} ${body.length}B');
  return body;
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  try {
    final json = await player(id, YoutubeApiClient.safari);
    final status = json['playabilityStatus'] as Map<String, dynamic>?;
    final data = json['streamingData'] as Map<String, dynamic>? ?? {};
    stdout.writeln(
      'status=${status?['status']} reason=${status?['reason']} '
      'dash=${data['dashManifestUrl'] != null} '
      'hls=${data['hlsManifestUrl'] != null}',
    );
    final hls = data['hlsManifestUrl'] as String?;
    if (hls == null) {
      final formats = (data['adaptiveFormats'] as List?)?.length ?? 0;
      stdout.writeln('no hls, formats=$formats');
      return;
    }
    final master = await getText(Uri.parse(hls));
    File('/tmp/hls_master.m3u8').writeAsStringSync(master);
    stdout.writeln(master.split('\n').take(24).join('\n'));

    final audioPlaylist = RegExp(
      r'^#EXT-X-MEDIA:TYPE=AUDIO.*$',
      multiLine: true,
    ).firstMatch(master);
    final variant =
        RegExp(r'^(?!#)(https?://\S+|/videoplayback\S*)$', multiLine: true)
            .allMatches(master)
            .map((m) => m.group(0)!)
            .firstWhere((_) => true, orElse: () => '');
    stdout.writeln('audio-line=${audioPlaylist?.group(0)}');
    stdout.writeln(
      'first-uri=${variant.substring(0, variant.length.clamp(0, 300))}',
    );

    final uris = RegExp(
      r'^(?!#)(\S+)$',
      multiLine: true,
    ).allMatches(master).map((m) => m.group(1)!).toList();
    stdout.writeln('uris=${uris.length}');
    var index = 0;
    for (final uri in uris.take(6)) {
      final resolved = Uri.parse(hls).resolve(uri);
      final isAudio = resolved.queryParameters['xtags'] != null;
      stdout.writeln(
        '  [$index] audio=$isAudio xtags=${resolved.queryParameters['xtags']}',
      );
      if (!isAudio) {
        index++;
        continue;
      }
      final playlist = await getText(resolved);
      final segments = playlist
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .toList();
      stdout.writeln('  segments=${segments.length}');
      for (final pick in [0, segments.length ~/ 2]) {
        final segment = Uri.parse(hls).resolve(segments[pick]);
        final response = await (await _client.getUrl(segment)).close();
        var read = 0;
        await for (final chunk in response) {
          read += chunk.length;
        }
        stdout.writeln(
          '  seg[$pick] -> ${response.statusCode} ${read}B '
          'range=${segment.queryParameters['range']}',
        );
      }
      break;
    }
  } catch (error) {
    stdout.writeln('failed: $error');
  } finally {
    _client.close(force: true);
  }
}

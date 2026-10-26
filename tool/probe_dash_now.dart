// Inspects DASH/HLS manifests of a multi audio video and tries one audio
// segment, to see whether per segment URLs bypass the 1 MiB progressive cap.
//
// Usage: dart run tool/probe_dash_now.dart [videoId]
//
// Deprecated clients stay in the matrix on purpose: the probe checks whether
// their manifests expose segments that bypass the progressive cap.
// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

const _clients = {
  'android': YoutubeApiClient.android,
  'androidSdkless': YoutubeApiClient.androidSdkless,
  'androidMusic': YoutubeApiClient.androidMusic,
  'androidVr': YoutubeApiClient.androidVr,
  'safari': YoutubeApiClient.safari,
  'tv': YoutubeApiClient.tv,
  'mediaConnect': YoutubeApiClient.mediaConnect,
  'mweb': YoutubeApiClient.mweb,
  'webCreator': YoutubeApiClient.webCreator,
  'tvSimplyEmbedded': YoutubeApiClient.tvSimplyEmbedded,
};

Future<Map<String, dynamic>> player(String id, YoutubeApiClient c) async {
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
  final body = await utf8.decodeStream(response);
  if (response.statusCode != 200) {
    throw StateError('HTTP ${response.statusCode}');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

Future<List<int>> getBytes(
  Uri url, {
  int start = 0,
  int? end,
  Map<String, String>? headers,
}) async {
  final request = await _client.getUrl(url);
  headers?.forEach(request.headers.set);
  if (end != null) {
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
  }
  final response = await request.close();
  final bytes = <int>[];
  await for (final chunk in response) {
    bytes.addAll(chunk);
  }
  stdout.writeln(
    '    GET ${response.statusCode} ${bytes.length}B '
    '${response.headers.value(HttpHeaders.contentRangeHeader) ?? ''}',
  );
  return bytes;
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  try {
    final json = await player(id, YoutubeApiClient.androidSdkless);
    for (final entry in _clients.entries) {
      try {
        final probe = await player(id, entry.value);
        final status = probe['playabilityStatus'] as Map<String, dynamic>?;
        final probeData = probe['streamingData'] as Map<String, dynamic>? ?? {};
        final formats = (probeData['adaptiveFormats'] as List?)?.length ?? 0;
        stdout.writeln(
          'client=${entry.key} status=${status?['status']} formats=$formats '
          'dash=${probeData['dashManifestUrl'] != null} '
          'hls=${probeData['hlsManifestUrl'] != null} '
          'reason=${status?['reason']}',
        );
      } catch (error) {
        stdout.writeln('client=${entry.key} failed: $error');
      }
    }
    final data = json['streamingData'] as Map<String, dynamic>? ?? {};
    final dash = data['dashManifestUrl'] as String?;
    final hls = data['hlsManifestUrl'] as String?;
    stdout.writeln('dash=$dash');
    stdout.writeln('hls=$hls');
    if (dash == null) return;
    final manifest = await getBytes(Uri.parse(dash));
    final text = utf8.decode(manifest, allowMalformed: true);
    File('/tmp/dash.mpd').writeAsStringSync(text);
    stdout.writeln(
      'mpd=${text.length}B sets=${'<AdaptationSet'.allMatches(text).length}',
    );
    for (final match in RegExp(
      r'<AdaptationSet[^>]*>',
    ).allMatches(text).take(8)) {
      stdout.writeln('  ${match.group(0)}');
    }
    final template = RegExp(
      r'<SegmentTemplate([^>]*)>',
    ).firstMatch(text)?.group(1);
    stdout.writeln('template=$template');
  } finally {
    _client.close(force: true);
  }
}

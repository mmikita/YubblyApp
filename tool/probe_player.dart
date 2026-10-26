// Dumps the raw player response flags per client: dash manifest, HLS manifest
// and format counts. This decides whether a fragment based stream is reachable.
//
// Usage: dart run tool/probe_player.dart [videoId]
//
// Deprecated clients stay in the matrix on purpose: the probe checks whether
// their player responses expose DASH or HLS manifests.
// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _clients = <String, YoutubeApiClient>{
  'androidSdkless': YoutubeApiClient.androidSdkless,
  'ios': YoutubeApiClient.ios,
  'safari': YoutubeApiClient.safari,
  'mweb': YoutubeApiClient.mweb,
  'webCreator': YoutubeApiClient.webCreator,
  'mediaConnect': YoutubeApiClient.mediaConnect,
  'tvSimplyEmbedded': YoutubeApiClient.tvSimplyEmbedded,
};

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final client = HttpClient();
  try {
    for (final entry in _clients.entries) {
      final c = entry.value;
      final uri = Uri.parse(c.apiUrl);
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      for (final header in c.headers.entries) {
        request.headers.set(header.key, '${header.value}');
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
      try {
        final response = await request.close().timeout(
          const Duration(seconds: 20),
        );
        final body = await utf8.decoder.bind(response).join();
        if (response.statusCode != 200) {
          stdout.writeln('${entry.key}: HTTP ${response.statusCode}');
          continue;
        }
        final json = jsonDecode(body) as Map<String, dynamic>;
        final status = json['playabilityStatus'] as Map<String, dynamic>?;
        final data = json['streamingData'] as Map<String, dynamic>? ?? const {};
        final dash = data['dashManifestUrl'] as String?;
        final hls = data['hlsManifestUrl'] as String?;
        stdout.writeln(
          '${entry.key}: status=${status?['status']} '
          'reason=${status?['reason']} '
          'dash=${dash == null ? '-' : dash.substring(0, 60)} '
          'hls=${hls == null ? '-' : hls.substring(0, 60)} '
          'formats=${(data['formats'] as List?)?.length ?? 0} '
          'adaptive=${(data['adaptiveFormats'] as List?)?.length ?? 0}',
        );
        if (hls != null) {
          final manifest = await (await client.getUrl(Uri.parse(hls))).close();
          final text = await utf8.decoder
              .bind(manifest)
              .join()
              .timeout(const Duration(seconds: 20));
          stdout.writeln('  hls ${manifest.statusCode}:');
          for (final line in const LineSplitter().convert(text).take(12)) {
            stdout.writeln('    $line');
          }
        }
      } catch (error) {
        stdout.writeln('${entry.key}: failed $error');
      }
    }
  } finally {
    client.close(force: true);
  }
}

// Tests the `range=` query form on `ios` client URLs, which ignore the Range
// header but may accept arbitrary offsets.
//
// Usage: dart run tool/probe_ios_query.dart [videoId]
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<void> probe(String label, Uri url, int start, int length) async {
  final target = url.replace(
    queryParameters: {
      ...url.queryParameters,
      'range': '$start-${start + length - 1}',
    },
  );
  final request = await _client.getUrl(target);
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
    '$label @${start ~/ 1024}K -> ${response.statusCode}/$read '
    '${response.headers.value(HttpHeaders.contentRangeHeader)}',
  );
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streams.getManifest(
      id,
      ytClients: [YoutubeApiClient.ios],
    );
    final stream = manifest.audioOnly
        .where((s) => s.fragments.isEmpty && s.tag == 140)
        .firstOrNull;
    if (stream == null) {
      stdout.writeln('no 140 stream: ${manifest.audioOnly.map((s) => s.tag)}');
      return;
    }
    final params = stream.url.queryParameters;
    stdout.writeln(
      'size=${stream.size.totalBytes} c=${params['c']} '
      'rqh=${params['rqh']} ratebypass=${params['ratebypass']}',
    );
    const size = 65536;
    await probe('query', stream.url, 0, size);
    await probe('query', stream.url, 512 << 10, size);
    await probe('query', stream.url, 1 << 20, size);
    await probe('query', stream.url, 2 << 20, size);
    await probe('query', stream.url, 10 << 20, size);
  } finally {
    _client.close(force: true);
    yt.close();
  }
}

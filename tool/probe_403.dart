// Inspects the body of googlevideo 403 responses and probes several offsets and
// range styles on one audio URL.
//
// Usage: dart run tool/probe_403.dart [videoId] [tag]
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<void> attempt(
  String label,
  Uri url,
  int start,
  int length, {
  bool query = false,
  bool full = false,
}) async {
  final end = full ? '' : '${start + length - 1}';
  final target = query
      ? url.replace(
          queryParameters: {
            ...url.queryParameters,
            'range': full ? '$start-' : '$start-$end',
          },
        )
      : url;
  final request = await _client.getUrl(target);
  if (!query) {
    request.headers.set(
      HttpHeaders.rangeHeader,
      full ? 'bytes=$start-' : 'bytes=$start-$end',
    );
  }
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  final response = await request.close();
  var read = 0;
  final head = <int>[];
  try {
    await for (final chunk in response) {
      read += chunk.length;
      if (head.length < 160) head.addAll(chunk.take(160 - head.length));
      if (read >= (1 << 20)) break;
    }
  } catch (_) {}
  final snippet = response.statusCode >= 300
      ? utf8.decode(head, allowMalformed: true).replaceAll('\n', ' ')
      : response.headers.value(HttpHeaders.contentRangeHeader);
  stdout.writeln('$label -> ${response.statusCode} read=$read $snippet');
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final tag = args.length > 1 ? int.parse(args[1]) : 140;
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streams.getManifest(id);
    final stream = manifest.audioOnly
        .where((s) => s.fragments.isEmpty && s.tag == tag)
        .firstWhere((s) => (s.audioTrack?.id ?? '').startsWith('en'));
    final url = stream.url;
    stdout.writeln('tag=$tag size=${stream.size.totalBytes}');
    stdout.writeln('url=$url');
    await attempt('header @0 64K', url, 0, 65536);
    await attempt('query  @2MiB 64K', url, 2 << 20, 65536, query: true);
    await attempt('header @2MiB 64K', url, 2 << 20, 65536);
    await attempt('header @1MiB 64K', url, 1 << 20, 65536);
    await attempt('header @1MiB+64K', url, (1 << 20) + 65536, 65536);
    await attempt('header @900K 64K', url, 900 << 10, 65536);
    await attempt('header @0 open', url, 0, 0, full: true);
  } finally {
    _client.close(force: true);
    yt.close();
  }
}

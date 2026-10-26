// Checks whether the ~1 MiB wall moves forward after consuming a URL
// sequentially (one URL used for consecutive, non-overlapping ranges).
//
// Usage: dart run tool/probe_seq.dart [videoId]
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final _client = HttpClient();

Future<int> fetch(Uri url, int start, int length) async {
  final request = await _client.getUrl(url);
  request.headers.set(
    HttpHeaders.rangeHeader,
    'bytes=$start-${start + length - 1}',
  );
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  final response = await request.close();
  var read = 0;
  try {
    await for (final chunk in response) {
      read += chunk.length;
    }
  } catch (_) {}
  stdout.writeln(
    '[$start+$length] -> ${response.statusCode}/$read '
    '${response.headers.value(HttpHeaders.contentRangeHeader)}',
  );
  return response.statusCode == 206 ? read : 0;
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streams.getManifest(id);
    final stream = manifest.audioOnly
        .where((s) => s.fragments.isEmpty && s.tag == 140)
        .firstWhere((s) => (s.audioTrack?.id ?? '').startsWith('en'));
    final url = stream.url;
    const mib = 1 << 20;
    stdout.writeln('size=${stream.size.totalBytes}');

    // 1. Consume the first megabyte in one go, then continue.
    final first = await fetch(url, 0, mib);
    if (first == mib) {
      await fetch(url, mib, 65536);
      await fetch(url, mib, mib);
    }

    // 2. Fresh URL: skip straight to the second megabyte.
    final other = (await yt.videos.streams.getManifest(id)).audioOnly
        .where((s) => s.fragments.isEmpty && s.tag == 140)
        .firstWhere((s) => (s.audioTrack?.id ?? '').startsWith('en'));
    stdout.writeln('-- fresh url');
    await fetch(other.url, mib, 65536);

    // 3. Fresh URL: half-megabyte chunks all the way to 2 MiB.
    final third = (await yt.videos.streams.getManifest(id)).audioOnly
        .where((s) => s.fragments.isEmpty && s.tag == 140)
        .firstWhere((s) => (s.audioTrack?.id ?? '').startsWith('en'));
    stdout.writeln('-- half-megabyte walk');
    for (var offset = 0; offset < 3 * mib; offset += 512 << 10) {
      await fetch(third.url, offset, 512 << 10);
    }
  } finally {
    _client.close(force: true);
    yt.close();
  }
}

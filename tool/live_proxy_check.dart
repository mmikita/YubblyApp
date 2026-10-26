// Live end-to-end check of the stream proxy against real YouTube URLs.
//
// Usage: dart run tool/live_proxy_check.dart [videoId]
//
// Uses the embedded web player and the bundled ejs n-signature solver (via
// Node) so the URLs are the same direct, multi-language URLs the app uses.
import 'dart:io';

import 'package:yubbly_app/stream_proxy.dart';
import 'package:yubbly_app/web_embedded.dart';

import 'node_solver.dart';

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final mp4Only = Platform.isMacOS || Platform.isIOS;
  final temp = Directory.systemTemp.createTempSync('yubbly-live-');
  final web = WebEmbeddedClient(challengeSolver: NodeChallengeSolver());
  final proxy = StreamProxy(cacheDir: Directory('${temp.path}/streams'));
  final client = HttpClient();

  try {
    await proxy.start();
    final manifest = await web.manifest(id);
    final tracks = <String, String>{};
    for (final s in manifest.audio) {
      if (mp4Only && s.container != 'mp4') continue;
      tracks.putIfAbsent(s.trackId, () => s.trackName);
    }
    stdout.writeln('tracks: $tracks');
    if (tracks.length < 2) {
      stdout.writeln('SKIP: fewer than two audio tracks');
      return;
    }
    final chosen = [
      for (final language in tracks.keys.take(2))
        manifest.selectAudio(language, mp4Only: mp4Only),
    ];

    final urls = <String>[];
    for (final stream in chosen) {
      urls.add(
        await proxy.register(
          ProxyTrack(
            length: stream.bytes,
            mimeType: stream.mimeType,
            mint: () async => stream.url,
          ),
        ),
      );
    }
    stdout.writeln('proxy: ${proxy.origin}');

    for (var i = 0; i < urls.length; i++) {
      final started = DateTime.now();
      final bytes = await _read(client, Uri.parse(urls[i]), 3 << 20);
      final elapsed = DateTime.now().difference(started);
      stdout.writeln(
        '${chosen[i].trackId}: $bytes bytes in '
        '${elapsed.inMilliseconds} ms',
      );
      if (bytes < (3 << 20)) {
        stdout.writeln('FAIL: track ${i + 1} delivered only $bytes bytes');
        exitCode = 1;
        return;
      }
    }
    stdout.writeln('OK: both tracks streamed through the proxy');
  } finally {
    await proxy.close();
    web.close();
    client.close(force: true);
    temp.deleteSync(recursive: true);
  }
}

/// Reads [wanted] bytes with sequential 64 KiB range requests, like a player.
Future<int> _read(HttpClient client, Uri url, int wanted) async {
  var total = 0;
  while (total < wanted) {
    final end = total + (64 << 10) - 1;
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$total-$end');
    final response = await request.close();
    if (response.statusCode != HttpStatus.partialContent) {
      stdout.writeln('unexpected status ${response.statusCode} at $total');
      await response.drain<void>();
      return total;
    }
    await for (final chunk in response) {
      total += chunk.length;
    }
  }
  return total;
}

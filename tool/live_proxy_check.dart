// Live end-to-end check of the stream proxy against real YouTube URLs.
//
// Usage: dart run tool/live_proxy_check.dart [videoId]
//
// Deliberately imports the plain-Dart proxy instead of `YoutubeRepository`,
// because the repository pulls in Flutter plugins (`path_provider`) and cannot
// run in a bare Dart VM. It selects two language tracks the same way the
// repository does, then reads the first few megabytes of each through the
// loopback server, verifying that ranges and URL re-minting hold up.
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:yubbly_app/stream_proxy.dart';

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final mp4Only = Platform.isMacOS || Platform.isIOS;
  final temp = Directory.systemTemp.createTempSync('yubbly-live-');
  final yt = YoutubeExplode();
  final proxy = StreamProxy(cacheDir: Directory('${temp.path}/streams'));
  final client = HttpClient();
  var mints = 0;

  Future<Uri?> mint(String language, int tag) async {
    mints++;
    final manifest = await yt.videos.streams.getManifest(id);
    final same = manifest.audioOnly.where(
      (s) => s.fragments.isEmpty && (s.audioTrack?.id ?? 'und') == language,
    );
    for (final s in same) {
      if (s.tag == tag) return s.url;
    }
    return same.firstOrNull?.url;
  }

  try {
    await proxy.start();
    final manifest = await yt.videos.streams.getManifest(id);
    final tracks = <String, String>{};
    for (final s in manifest.audioOnly.where((s) => s.fragments.isEmpty)) {
      if (mp4Only && s.container.name != 'mp4') continue;
      tracks.putIfAbsent(
        s.audioTrack?.id ?? 'und',
        () => s.audioTrack?.displayName ?? 'und',
      );
    }
    stdout.writeln('tracks: $tracks');
    if (tracks.length < 2) {
      stdout.writeln('SKIP: fewer than two audio tracks');
      return;
    }
    final ids = tracks.keys.toList();
    final chosen = [
      for (final language in ids.take(2))
        manifest.audioOnly
            .where(
              (s) =>
                  s.fragments.isEmpty &&
                  (s.audioTrack?.id ?? 'und') == language &&
                  (!mp4Only || s.container.name == 'mp4'),
            )
            .reduce(
              (a, b) =>
                  b.bitrate.bitsPerSecond > a.bitrate.bitsPerSecond ? b : a,
            ),
    ];

    final urls = <String>[];
    for (final stream in chosen) {
      final language = stream.audioTrack?.id ?? 'und';
      urls.add(
        await proxy.register(
          ProxyTrack(
            length: stream.size.totalBytes,
            mimeType: 'audio/mp4',
            mint: () => mint(language, stream.tag),
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
        '${chosen[i].audioTrack?.id}: $bytes bytes in '
        '${elapsed.inMilliseconds} ms, mints so far=$mints',
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
    yt.close();
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

// Live end-to-end check of the offline audio downloader.
//
// Usage: dart run tool/live_offline_check.dart [videoId]
//
// Uses the embedded web player + ejs solver (via Node), downloads the first two
// language tracks with AudioDownloader, checks their byte counts and removes
// the temporary files.
import 'dart:io';

import 'package:yubbly_app/audio_downloader.dart';
import 'package:yubbly_app/web_embedded.dart';

import 'node_solver.dart';

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
  final mp4Only = Platform.isMacOS || Platform.isIOS;
  final temp = Directory.systemTemp.createTempSync('yubbly-offline-');
  final web = WebEmbeddedClient(challengeSolver: NodeChallengeSolver());
  final client = HttpClient();

  try {
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

    for (final language in tracks.keys.take(2)) {
      final stream = manifest.selectAudio(language, mp4Only: mp4Only);
      final extension = stream.container == 'mp4' ? 'm4a' : 'webm';
      final target = File('${temp.path}/$language.$extension');
      final started = DateTime.now();
      stdout.writeln(
        'selected $language tag=${stream.tag} '
        'container=${stream.container} bitrate=${stream.bitrate} '
        'total=${stream.bytes}',
      );
      await AudioDownloader(client: client).download(
        spec: AudioDownloadSpec(
          initialUrl: stream.url,
          totalBytes: stream.bytes,
        ),
        destination: target,
        mint: () async => stream.url,
        onProgress: (received, total) {
          stdout.writeln('progress $language: $received/$total');
        },
      );
      final length = await target.length();
      final elapsed = DateTime.now().difference(started);
      if (length != stream.bytes) {
        stdout.writeln('FAIL: $language expected ${stream.bytes}, got $length');
        exitCode = 1;
        return;
      }
      stdout.writeln(
        'OK: $language ${stream.container} '
        '${stream.bitrate ~/ 1000} kbps, $length bytes, '
        '${elapsed.inSeconds}s',
      );
    }
    stdout.writeln('OK: offline downloader completed both tracks');
  } finally {
    web.close();
    client.close(force: true);
    temp.deleteSync(recursive: true);
  }
}

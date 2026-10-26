import 'dart:io';
import 'package:yubbly_app/youtube_repository.dart';

// Opt-in network smoke test: simultaneous English/Polish streams, bounded RAM only.
Future<void> main(List<String> args) async {
  final repo = YoutubeRepository();
  try {
    final id = args.isEmpty ? 'zA-UHB2WcT4' : args.first;
    final d = await repo.inspect(id);
    stdout.writeln('${d.video.title}\n${d.video.channelUrl}');
    for (final t in d.tracks) {
      stdout.writeln('${t.id}: ${t.label}');
    }
    final a = d.tracks.firstWhere((t) => t.id.startsWith('en'));
    final b = d.tracks.firstWhere((t) => t.id.startsWith('pl'));
    final urls = await repo.streams(id, a.id, b.id, video: false);
    await Future.wait(
      ['urlA', 'urlB'].map((key) async {
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse(urls[key] as String));
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-4095');
          final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
          if (response.statusCode != 200 && response.statusCode != 206) {
            throw StateError('$key HTTP ${response.statusCode}');
          }
          var count = 0;
          await for (final chunk in response.timeout(
            const Duration(seconds: 20),
          )) {
            count += chunk.length;
            if (count >= 4096) break;
          }
          stdout.writeln(
            '$key content-length=${response.contentLength}, content-range=${response.headers.value(HttpHeaders.contentRangeHeader)}, type=${response.headers.contentType}, query-range=${Uri.parse(urls[key] as String).queryParameters["range"]}',
          );
          if (response.headers.contentType?.mimeType == 'text/html') {
            throw StateError(
              '$key returned HTML instead of audio; media host unavailable in this network.',
            );
          }
          if (count < 1024) {
            throw StateError(
              '$key unexpectedly short media response: $count bytes',
            );
          }
          stdout.writeln(
            '$key: HTTP ${response.statusCode}, $count bytes, ${response.headers.contentType}',
          );
        } finally {
          client.close(force: true);
        }
      }),
    );
  } catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } finally {
    repo.close();
  }
}

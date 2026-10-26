import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yubbly_app/audio_downloader.dart';

/// Stands in for googlevideo: each minted URL has a one-megabyte budget and
/// optionally accepts ranges only as a `range=` query parameter.
class _FakeMediaHost {
  _FakeMediaHost(this.payload, {this.queryRangeOnly = false});

  static const budget = 1 << 20;

  final Uint8List payload;
  final bool queryRangeOnly;
  HttpServer? _server;
  int _tokens = 0;
  final Map<int, int> _spent = {};
  int requests = 0;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server!.port}/media');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<Uri> mint() async {
    final token = _tokens++;
    return uri.replace(queryParameters: {'token': '$token'});
  }

  Future<void> _handle(HttpRequest request) async {
    requests++;
    final response = request.response;
    final token = int.tryParse(request.uri.queryParameters['token'] ?? '');
    final spent = token == null ? -1 : _spent[token] ?? 0;
    if (token == null || token >= _tokens || spent >= budget) {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }
    final header = request.headers.value(HttpHeaders.rangeHeader);
    if (queryRangeOnly && header != null) {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }
    final queryRange = request.uri.queryParameters['range'];
    final range = queryRange ?? header;
    var start = 0;
    var end = payload.length - 1;
    if (range != null) {
      final value = range.startsWith('bytes=') ? range.substring(6) : range;
      final parts = value.split('-');
      start = int.parse(parts[0]);
      if (parts.length > 1 && parts[1].isNotEmpty) {
        end = min(int.parse(parts[1]), end);
      }
      if (start >= payload.length) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await response.close();
        return;
      }
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${payload.length}',
      );
    }
    final available = budget - spent;
    final length = min(end - start + 1, available);
    _spent[token] = spent + length;
    response.contentLength = length;
    response.headers.contentType = ContentType('audio', 'mp4');
    response.add(Uint8List.sublistView(payload, start, start + length));
    await response.close();
  }

  Future<void> close() async {
    await _server?.close(force: true);
  }
}

void main() {
  late Directory root;
  late _FakeMediaHost host;
  late Uint8List payload;
  final random = Random(11);

  setUp(() async {
    // 2.5 MiB needs three one-megabyte URLs.
    payload = Uint8List.fromList(
      List<int>.generate(
        (2.5 * 1024 * 1024).round(),
        (_) => random.nextInt(256),
      ),
    );
    root = await Directory.systemTemp.createTemp('yubbly_download');
    host = _FakeMediaHost(payload);
    await host.start();
  });

  tearDown(() async {
    await host.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> download(
    AudioDownloader downloader, {
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final initial = await host.mint();
    return downloader.download(
      spec: AudioDownloadSpec(initialUrl: initial, totalBytes: payload.length),
      destination: File('${root.path}/track.m4a'),
      mint: host.mint,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  test('writes the whole track across one-shot URLs', () async {
    final progress = <int>[];
    final file = await download(
      AudioDownloader(segmentSize: 1 << 20),
      onProgress: (received, _) => progress.add(received),
    );
    expect(await file.readAsBytes(), payload);
    expect(progress.last, payload.length);
    expect(host.requests, greaterThan(2));
  });

  test('falls back to the range query parameter used by iOS URLs', () async {
    await host.close();
    host = _FakeMediaHost(payload, queryRangeOnly: true);
    await host.start();
    final file = await download(AudioDownloader(segmentSize: 1 << 20));
    expect(await file.readAsBytes(), payload);
  });

  test('refreshes a rejected URL instead of reusing the cached one', () async {
    final destination = File('${root.path}/track.m4a');
    final stale = await host.mint();
    var refreshes = 0;
    final file = await AudioDownloader(segmentSize: 1 << 20).download(
      spec: AudioDownloadSpec(initialUrl: stale, totalBytes: payload.length),
      destination: destination,
      mint: () async => stale,
      refreshMint: () async {
        refreshes++;
        return host.mint();
      },
    );
    expect(await file.readAsBytes(), payload);
    expect(refreshes, greaterThan(0));
  });

  test('resumes a partial segment file', () async {
    final destination = File('${root.path}/track.m4a');
    final part = File('${destination.path}.part');
    await part.writeAsBytes(payload.sublist(0, 1 << 20));
    final progress = <int>[];
    final file = await download(
      AudioDownloader(segmentSize: 1 << 20),
      onProgress: (received, _) => progress.add(received),
    );
    expect(progress.first, 1 << 20);
    expect(await file.readAsBytes(), payload);
  });

  test('leaves a resumable part file after cancellation', () async {
    final destination = File('${root.path}/track.m4a');
    var cancelled = false;
    await expectLater(
      download(
        AudioDownloader(segmentSize: 1 << 20),
        isCancelled: () => cancelled,
        onProgress: (received, _) {
          if (received >= 1 << 20) cancelled = true;
        },
      ),
      throwsA(isA<DownloadCancelled>()),
    );
    final part = File('${destination.path}.part');
    expect(await part.exists(), isTrue);
    expect(await part.length(), greaterThanOrEqualTo(1 << 20));
    expect(await destination.exists(), isFalse);
  });
}

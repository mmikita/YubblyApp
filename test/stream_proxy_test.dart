import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yubbly_app/stream_proxy.dart';

/// Stands in for `googlevideo.com`.
///
/// Mirrors the two behaviours that break playback in production:
///  * each minted URL stops serving after [budget] bytes and then answers `403`
///    (in production the budget is about one megabyte),
///  * `ios` URLs answer `403` when the range arrives as a `Range` header and
///    only honour it as a `range=` query parameter.
class _FakeMediaHost {
  _FakeMediaHost(this.payload, {this.queryRangeOnly = false});

  static const budget = 1 << 20;

  final Uint8List payload;
  final bool queryRangeOnly;
  HttpServer? _server;
  int tokens = 0;
  int requests = 0;
  final Map<int, int> _spent = {};

  Uri get uri => Uri.parse('http://127.0.0.1:${_server!.port}/media');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<Uri> mint() async {
    final token = tokens++;
    return uri.replace(queryParameters: {'token': '$token'});
  }

  Future<void> _handle(HttpRequest request) async {
    requests++;
    final response = request.response;
    final token = int.tryParse(request.uri.queryParameters['token'] ?? '');
    final spent = token == null ? -1 : _spent[token] ?? 0;
    if (token == null || token >= tokens || spent >= budget) {
      // A spent or unknown URL answers exactly like the real host.
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
      response.contentLength = end - start + 1;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${payload.length}',
      );
    }
    final available = budget - spent;
    final length = min(end - start + 1, available);
    _spent[token] = spent + length;
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
  late StreamProxy proxy;
  late Uint8List payload;
  final random = Random(7);

  setUp(() async {
    // 3.5 MiB, so a full read needs four one-megabyte URLs.
    payload = Uint8List.fromList(
      List<int>.generate(
        (3.5 * 1024 * 1024).round(),
        (_) => random.nextInt(256),
      ),
    );
    root = await Directory.systemTemp.createTemp('yubbly_proxy');
    host = _FakeMediaHost(payload);
    await host.start();
    proxy = StreamProxy(cacheDir: Directory('${root.path}/default'));
    await proxy.start();
  });

  tearDown(() async {
    await proxy.close();
    await host.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> register(StreamProxy target) => target.register(
    ProxyTrack(length: payload.length, mimeType: 'audio/mp4', mint: host.mint),
  );

  Future<(int, HttpHeaders, Uint8List)> fetch(
    String url, {
    String? range,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      if (range != null) {
        request.headers.set(HttpHeaders.rangeHeader, range);
      }
      final response = await request.close();
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return (response.statusCode, response.headers, builder.takeBytes());
    } finally {
      client.close(force: true);
    }
  }

  test('answers the two-byte probe AVFoundation sends first', () async {
    final url = await register(proxy);
    final (status, headers, body) = await fetch(url, range: 'bytes=0-1');
    expect(status, HttpStatus.partialContent);
    expect(
      headers.value(HttpHeaders.contentRangeHeader),
      'bytes 0-1/${payload.length}',
    );
    expect(headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(headers.contentType!.mimeType, 'audio/mp4');
    expect(body, payload.sublist(0, 2));
  });

  test('streams a whole track across many one-shot upstream URLs', () async {
    final url = await register(proxy);
    final (status, headers, body) = await fetch(url, range: 'bytes=0-');
    expect(status, HttpStatus.partialContent);
    expect(headers.contentLength, payload.length);
    expect(body, payload);
    // One fresh URL per megabyte, never a spent one.
    expect(host.tokens, greaterThanOrEqualTo(4));
  });

  test('serves a seek without reading from the start', () async {
    final url = await register(proxy);
    final (status, _, body) = await fetch(url, range: 'bytes=2000000-2499999');
    expect(status, HttpStatus.partialContent);
    expect(body, payload.sublist(2000000, 2500000));
  });

  test('rejects unsatisfiable ranges with 416 and the real length', () async {
    final url = await register(proxy);
    final (status, headers, _) = await fetch(url, range: 'bytes=99999999-');
    expect(status, HttpStatus.requestedRangeNotSatisfiable);
    expect(
      headers.value(HttpHeaders.contentRangeHeader),
      'bytes */${payload.length}',
    );
  });

  test('falls back to a range= query parameter for ios-style URLs', () async {
    final ios = _FakeMediaHost(payload, queryRangeOnly: true);
    await ios.start();
    try {
      final url = await proxy.register(
        ProxyTrack(
          length: payload.length,
          mimeType: 'audio/mp4',
          mint: ios.mint,
        ),
      );
      final (status, headers, body) = await fetch(url, range: 'bytes=0-');
      expect(status, HttpStatus.partialContent);
      expect(headers.contentLength, payload.length);
      expect(body, payload);
      expect(ios.requests, greaterThanOrEqualTo(8));
    } finally {
      await ios.close();
    }
  });

  test('small segments still cover the whole track', () async {
    final small = StreamProxy(
      cacheDir: Directory('${root.path}/small'),
      segmentSize: 1 << 16,
    );
    try {
      final url = await register(small);
      final (status, _, body) = await fetch(url, range: 'bytes=0-');
      expect(status, HttpStatus.partialContent);
      expect(body, payload);
    } finally {
      await small.close();
    }
  });

  test('serves media whose first byte looks like markup', () async {
    final tiny = Uint8List.fromList([
      0x3c,
      ...List<int>.generate(4095, (index) => index & 0xff),
    ]);
    final small = _FakeMediaHost(tiny);
    await small.start();
    try {
      final url = await proxy.register(
        ProxyTrack(
          length: tiny.length,
          mimeType: 'audio/mp4',
          mint: small.mint,
        ),
      );
      final (status, _, body) = await fetch(url, range: 'bytes=0-');
      expect(status, HttpStatus.partialContent);
      expect(body, tiny);
    } finally {
      await small.close();
    }
  });

  test('released tracks disappear from the cache', () async {
    final url = await register(proxy);
    await proxy.release();
    final (status, _, _) = await fetch(url, range: 'bytes=0-1');
    expect(status, HttpStatus.notFound);
  });
}

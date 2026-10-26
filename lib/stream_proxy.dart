import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Produces a fresh upstream URL for a registered track.
///
/// YouTube media URLs are short-lived: each one delivers only about a
/// megabyte of a single stream before the host starts answering `403`. The
/// proxy therefore asks for a new URL for every segment it downloads.
typedef StreamUrlMinter = Future<Uri?> Function();

/// Description of one remote track served by [StreamProxy].
class ProxyTrack {
  ProxyTrack({
    required this.length,
    required this.mimeType,
    required this.mint,
    this.refreshMint,
  });

  /// Total size of the remote stream in bytes.
  final int length;

  /// MIME type reported to the player, e.g. `audio/mp4`.
  final String mimeType;

  /// Mints an upstream URL for this track, usually from a cached manifest.
  final StreamUrlMinter mint;

  /// Mints a genuinely fresh URL after [mint] produced a rejected one. When
  /// omitted, [mint] is retried.
  final StreamUrlMinter? refreshMint;
}

/// Local HTTP server that makes YouTube media URLs playable by AVFoundation and
/// ExoPlayer.
///
/// Players request byte ranges with a `Range` header and expect `206 Partial
/// Content`. YouTube's `ios` URLs instead accept the range only as a `range=`
/// query parameter, and no URL serves more than roughly one megabyte. The proxy
/// normalises both problems: it turns player ranges into upstream requests,
/// caches the bytes in fixed 1 MiB segments on disk and mints a new URL whenever
/// the host rejects one.
class StreamProxy {
  StreamProxy({
    required this.cacheDir,
    this.segmentSize = 1 << 20,
    this.prefetchSegments = 4,
    this.keepBehindBytes = 64 << 20,
    this.attempts = 4,
  });

  /// Directory for the segment cache. Cleared on [start].
  final Directory cacheDir;

  /// Size of one cached segment. Must stay within the per-URL budget of the
  /// media host, so one fresh URL is minted for each segment.
  final int segmentSize;

  /// How many segments beyond the last requested one are downloaded ahead.
  final int prefetchSegments;

  /// Segments further than this behind the read position are deleted.
  final int keepBehindBytes;

  /// Upstream attempts per segment before the download is given up.
  final int attempts;

  final Map<String, _Track> _tracks = {};
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 15);
  HttpServer? _server;
  int _nextId = 0;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;
  String get origin => 'http://127.0.0.1:$port';

  /// Binds the loopback server and resets the cache directory.
  Future<void> start() async {
    if (_server != null) return;
    await cacheDir.create(recursive: true);
    await _clearCacheDir();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.idleTimeout = const Duration(seconds: 30);
    server.listen(_serve, onError: (Object _) {}, cancelOnError: false);
    _server = server;
  }

  /// Registers a track and returns the URL to hand to the platform player.
  Future<String> register(ProxyTrack track) async {
    await start();
    final id = 't${_nextId++}';
    final dir = Directory('${cacheDir.path}/$id');
    await dir.create(recursive: true);
    _tracks[id] = _Track(
      spec: track,
      dir: dir,
      client: _client,
      segmentSize: segmentSize,
      prefetchSegments: prefetchSegments,
      keepBehindSegments: max(0, keepBehindBytes ~/ segmentSize),
      attempts: attempts,
    );
    return '$origin/media/$id';
  }

  /// Forgets every registered track and removes its cached segments.
  Future<void> release() async {
    final tracks = _tracks.values.toList();
    _tracks.clear();
    for (final track in tracks) {
      await track.dispose();
    }
  }

  /// Stops the server, releases tracks and closes upstream connections.
  Future<void> close() async {
    await release();
    _client.close(force: true);
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _clearCacheDir() async {
    await for (final entity in cacheDir.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // A leftover file is harmless: tracks use fresh directories.
      }
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final track = segments.length == 2 && segments.first == 'media'
          ? _tracks[segments.last]
          : null;
      if (track == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      final length = track.length;
      final header = request.headers.value(HttpHeaders.rangeHeader);
      final range = _parseRange(header, length);
      if (range == null && header != null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        await response.close();
        return;
      }

      final start = range?.$1 ?? 0;
      final end = range?.$2 ?? length - 1;
      response.statusCode = range == null
          ? HttpStatus.ok
          : HttpStatus.partialContent;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.contentTypeHeader, track.mimeType);
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.contentLength = end - start + 1;
      if (range != null) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$length',
        );
      }
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }

      response.bufferOutput = false;
      var position = start;
      while (position <= end) {
        final index = position ~/ segmentSize;
        final data = await track.segment(index);
        final from = position - index * segmentSize;
        final to = min(data.length, end - index * segmentSize + 1);
        if (to <= from) break;
        response.add(Uint8List.sublistView(data, from, to));
        await response.flush();
        position += to - from;
      }
      await response.close();
    } catch (error) {
      if (Platform.environment['YUBBLY_PROXY_DEBUG'] == '1') {
        stderr.writeln('proxy: ${request.uri} failed: $error');
      }
      // The player cancels requests on every seek; drop the connection quietly.
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Parses `bytes=a-b`, `bytes=a-` and `bytes=-n` into inclusive bounds.
  static (int, int)? _parseRange(String? header, int length) {
    if (header == null) return null;
    final value = header.trim().toLowerCase();
    if (!value.startsWith('bytes=')) return null;
    final parts = value.substring(6).split(',').first.split('-');
    if (parts.length != 2) return null;
    final rawStart = parts[0].trim();
    final rawEnd = parts[1].trim();
    if (rawStart.isEmpty) {
      final suffix = int.tryParse(rawEnd);
      if (suffix == null || suffix <= 0) return null;
      if (length == 0) return null;
      return (max(0, length - suffix), length - 1);
    }
    final start = int.tryParse(rawStart);
    if (start == null || start < 0 || start >= length) return null;
    final end = rawEnd.isEmpty ? length - 1 : int.tryParse(rawEnd);
    if (end == null || end < start) return null;
    return (start, min(end, length - 1));
  }
}

/// One registered track: a disk-backed, segmented byte range.
class _Track {
  _Track({
    required this.spec,
    required this.dir,
    required HttpClient client,
    required this.segmentSize,
    required this.prefetchSegments,
    required this.keepBehindSegments,
    required this.attempts,
  }) : _client = client;

  final ProxyTrack spec;
  final Directory dir;
  final HttpClient _client;
  final int segmentSize;
  final int prefetchSegments;
  final int keepBehindSegments;
  final int attempts;

  static const _memorySegments = 6;

  final Map<int, Uint8List> _memory = <int, Uint8List>{};
  final Set<int> _onDisk = {};
  final Map<int, Completer<Uint8List>> _waiters = {};
  final Set<int> _demand = {};
  final Set<int> _inflight = {};
  bool _pumping = false;
  bool _closed = false;
  int _cursor = 0;

  int get length => spec.length;
  String get mimeType => spec.mimeType;
  int get _count => max(1, (length + segmentSize - 1) ~/ segmentSize);

  File _file(int index) => File('${dir.path}/$index.seg');

  /// Records the segment the player is currently reading, which drives
  /// prefetching and cache eviction.
  void touch(int index) => _cursor = index;

  /// Returns segment [index], downloading it on demand.
  Future<Uint8List> segment(int index) async {
    if (index < 0 || index >= _count) return Uint8List(0);
    _cursor = index;
    final cached = _memory[index];
    if (cached != null) return cached;
    final file = _file(index);
    if (_onDisk.contains(index) && await file.exists()) {
      final bytes = await file.readAsBytes();
      _remember(index, bytes);
      return bytes;
    }
    if (_closed) return Uint8List(0);
    _demand.add(index);
    final waiter = _waiters.putIfAbsent(index, Completer<Uint8List>.new);
    _pump();
    return waiter.future;
  }

  Future<void> _pump() async {
    if (_pumping || _closed) return;
    _pumping = true;
    try {
      while (!_closed) {
        final index = _next();
        if (index == null) break;
        _inflight.add(index);
        try {
          final bytes = await _download(index);
          _onDisk.add(index);
          _remember(index, bytes);
          _waiters.remove(index)?.complete(bytes);
        } catch (error) {
          _waiters.remove(index)?.completeError(error);
        } finally {
          _demand.remove(index);
          _inflight.remove(index);
        }
        await _evict();
      }
    } finally {
      _pumping = false;
    }
    if (!_closed && _next() != null) _pump();
  }

  int? _next() {
    int? demand;
    for (final index in _demand) {
      if (_inflight.contains(index) || _onDisk.contains(index)) continue;
      if (demand == null || index < demand) demand = index;
    }
    if (demand != null) return demand;
    final limit = min(_count, _cursor + prefetchSegments + 1);
    for (var index = _cursor; index < limit; index++) {
      if (_inflight.contains(index) || _onDisk.contains(index)) continue;
      return index;
    }
    return null;
  }

  Future<Uint8List> _download(int index) async {
    final start = index * segmentSize;
    final end = min(length, start + segmentSize) - 1;
    final wanted = end - start + 1;
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      if (_closed) throw StateError('Zamknięto pamięć podręczną strumienia.');
      try {
        // The first attempt may reuse a cached manifest. Later attempts ask for
        // a fresh manifest so an expired URL cannot be handed out repeatedly.
        final minter = attempt == 1
            ? spec.mint
            : (spec.refreshMint ?? spec.mint);
        final url = await minter();
        if (url == null) throw StateError('Brak adresu strumienia.');
        var bytes = await _safeFetch(url, start, wanted, useQueryRange: false);
        // `ios` URLs reject the header form outright; retry with `range=`.
        bytes ??= await _safeFetch(url, start, wanted, useQueryRange: true);
        if (bytes != null) {
          await _file(index).writeAsBytes(bytes, flush: true);
          return bytes;
        }
        lastError = StateError('Host odrzucił zakres $start-$end.');
      } catch (error) {
        lastError = error;
      }
      // A spent URL is normal: refresh it immediately, but back off a little so
      // rapid seeks do not hammer the player API.
      await Future<void>.delayed(Duration(milliseconds: 120 * attempt));
    }
    throw StateError('Nie udało się pobrać fragmentu strumienia: $lastError');
  }

  /// [_fetch] that reports every transport failure as `null` so the caller can
  /// fall back to the query form or a fresh URL.
  Future<Uint8List?> _safeFetch(
    Uri url,
    int start,
    int wanted, {
    required bool useQueryRange,
  }) async {
    try {
      return await _fetch(url, start, wanted, useQueryRange: useQueryRange);
    } catch (_) {
      return null;
    }
  }

  /// Reads [wanted] bytes from [url] starting at [start], or returns `null`.
  ///
  /// YouTube's `ios` URLs ignore the `Range` header and answer `403`; for those
  /// the range has to travel as a `range=` query parameter.
  Future<Uint8List?> _fetch(
    Uri url,
    int start,
    int wanted, {
    required bool useQueryRange,
  }) async {
    final end = start + wanted - 1;
    final target = useQueryRange
        ? url.replace(
            queryParameters: {...url.queryParameters, 'range': '$start-$end'},
          )
        : url;
    final request = await _client.getUrl(target);
    if (!useQueryRange) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    }
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close();
    final status = response.statusCode;
    if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
      await response.drain<void>();
      return null;
    }
    final type = response.headers.contentType?.mimeType ?? '';
    final bytes = await _read(
      response,
      status == HttpStatus.ok ? start : 0,
      wanted,
    );
    if (bytes == null) return null;
    // A refused network answers with a small HTML page; never hand that to the
    // decoder. Check the markup, not a single byte: media bytes can be `<` too.
    if (type == 'text' || type == 'text/html') return null;
    final head = String.fromCharCodes(bytes.take(16)).toLowerCase();
    if (head.startsWith('<!doctype') || head.startsWith('<html')) return null;
    return bytes;
  }

  static Future<Uint8List?> _read(
    HttpClientResponse response,
    int skip,
    int wanted,
  ) async {
    final builder = BytesBuilder(copy: false);
    var toSkip = skip;
    try {
      await for (final chunk in response) {
        var view = chunk;
        if (toSkip > 0) {
          final drop = min(toSkip, view.length);
          toSkip -= drop;
          if (drop == view.length) continue;
          view = view.sublist(drop);
        }
        builder.add(view);
        if (builder.length >= wanted) break;
      }
    } catch (_) {
      return null;
    }
    final bytes = builder.takeBytes();
    if (bytes.length < wanted) return null;
    return Uint8List.sublistView(bytes, 0, wanted);
  }

  void _remember(int index, Uint8List bytes) {
    _memory.remove(index);
    _memory[index] = bytes;
    while (_memory.length > _memorySegments) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<void> _evict() async {
    if (keepBehindSegments <= 0) return;
    final limit = _cursor - keepBehindSegments;
    if (limit <= 0) return;
    final stale = _onDisk.where((index) => index < limit).toList();
    for (final index in stale) {
      _onDisk.remove(index);
      _memory.remove(index);
      try {
        await _file(index).delete();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _closed = true;
    for (final waiter in _waiters.values) {
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('Zamknięto strumień.'));
      }
    }
    _waiters.clear();
    _memory.clear();
    _onDisk.clear();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

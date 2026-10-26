import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Produces a fresh upstream URL for the next segment.
///
/// YouTube media URLs stop serving after roughly one megabyte, so a full-track
/// download has to mint a new URL for every segment.
typedef AudioUrlMinter = Future<Uri?> Function();

/// Everything the downloader needs to know about one remote audio stream.
class AudioDownloadSpec {
  const AudioDownloadSpec({required this.initialUrl, required this.totalBytes});

  final Uri initialUrl;
  final int totalBytes;
}

/// Thrown when the caller asks the download to stop. The partial `.part` file
/// is left on disk so the next attempt can resume it.
class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => 'Pobieranie anulowane.';
}

/// Downloads a progressive audio stream into one local file.
///
/// The remote host accepts roughly one megabyte per signed URL. The downloader
/// therefore writes the file in fixed-size segments, mints a fresh URL for each
/// segment, retries a segment up to [attempts] times and resumes from the last
/// complete segment left by an earlier attempt.
class AudioDownloader {
  AudioDownloader({
    HttpClient? client,
    this.segmentSize = 1 << 20,
    this.attempts = 4,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient(),
       _ownsClient = client == null {
    _client.connectionTimeout = requestTimeout;
    _client.idleTimeout = const Duration(seconds: 15);
  }

  /// Size of one request. Kept within the per-URL budget of the media host.
  final int segmentSize;

  /// Upstream attempts per segment before the download is given up.
  final int attempts;

  final Duration requestTimeout;
  final HttpClient _client;
  final bool _ownsClient;

  /// Downloads [spec] to [destination] and returns the completed file.
  ///
  /// [mint] is called before every segment except the first one, which uses
  /// [AudioDownloadSpec.initialUrl]. When a segment is rejected, [refreshMint]
  /// is used for the retry so a cached manifest can be bypassed and a genuinely
  /// new URL requested. [onProgress] receives bytes written so far and the total
  /// size. [isCancelled] is polled between segments and while reading a
  /// response.
  Future<File> download({
    required AudioDownloadSpec spec,
    required File destination,
    AudioUrlMinter? mint,
    AudioUrlMinter? refreshMint,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = spec.totalBytes;
    if (total <= 0) {
      throw const FormatException('Nieznany rozmiar strumienia audio.');
    }
    await destination.parent.create(recursive: true);
    final temp = File('${destination.path}.part');
    var existing = await temp.exists() ? await temp.length() : 0;
    if (existing > total) {
      await temp.delete();
      existing = 0;
    }
    // Only whole segments are trusted; a torn last segment is downloaded again.
    var completed = (existing ~/ segmentSize) * segmentSize;
    final raf = await temp.open(mode: FileMode.append);
    if (completed > 0) {
      await raf.truncate(completed);
    }
    await raf.setPosition(completed);
    try {
      onProgress?.call(completed, total);
      while (completed < total) {
        if (isCancelled?.call() ?? false) throw const DownloadCancelled();
        final wanted = min(segmentSize, total - completed);
        final bytes = await _downloadSegment(
          spec: spec,
          start: completed,
          wanted: wanted,
          mint: mint,
          refreshMint: refreshMint,
          isCancelled: isCancelled,
        );
        if (bytes == null) {
          throw StateError(
            'Nie udało się pobrać fragmentu ${completed ~/ segmentSize + 1}. '
            'Sprawdź połączenie i spróbuj ponownie.',
          );
        }
        await raf.writeFrom(bytes);
        completed += bytes.length;
        onProgress?.call(completed, total);
      }
      await raf.flush();
    } finally {
      await raf.close();
    }
    if (await destination.exists()) await destination.delete();
    await temp.rename(destination.path);
    return destination;
  }

  Future<Uint8List?> _downloadSegment({
    required AudioDownloadSpec spec,
    required int start,
    required int wanted,
    required AudioUrlMinter? mint,
    required AudioUrlMinter? refreshMint,
    required bool Function()? isCancelled,
  }) async {
    Uri? url = start == 0 ? spec.initialUrl : null;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (isCancelled?.call() ?? false) throw const DownloadCancelled();
      if (url == null) {
        try {
          // The first request may reuse a cached manifest URL. A retry must
          // force a new manifest, otherwise a stale URL is handed out again.
          final minter = attempt == 0 ? mint : (refreshMint ?? mint);
          url = await minter?.call();
        } catch (_) {
          url = null;
        }
      }
      if (url == null) return null;
      var bytes = await _safeFetch(url, start, wanted, useQueryRange: false);
      bytes ??= await _safeFetch(url, start, wanted, useQueryRange: true);
      if (bytes != null) return bytes;
      // A rejected URL is spent; ask for a new one before retrying.
      url = null;
    }
    return null;
  }

  Future<Uint8List?> _safeFetch(
    Uri url,
    int start,
    int wanted, {
    required bool useQueryRange,
  }) async {
    try {
      return await _fetch(
        url,
        start,
        wanted,
        useQueryRange: useQueryRange,
      ).timeout(requestTimeout);
    } catch (_) {
      return null;
    }
  }

  /// Reads [wanted] bytes from [url] starting at [start], or returns `null`.
  ///
  /// Some YouTube `ios` URLs ignore the `Range` header and answer `403`; for
  /// those the range has to travel as a `range=` query parameter.
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
    // A refused network answers with a small HTML page; never store that as
    // audio. Check the markup, not a single byte: media bytes can be `<` too.
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

  void dispose() {
    if (_ownsClient) _client.close(force: true);
  }
}

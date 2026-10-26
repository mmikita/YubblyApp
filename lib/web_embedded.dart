import 'dart:convert';
import 'dart:io';

/// Turns YouTube's `n` challenge into the value accepted by the media host.
abstract class NChallengeSolver {
  Future<String?> solveN({
    required String playerUrl,
    required String playerJs,
    required String challenge,
  });
}

/// One audio-only stream returned by the embedded YouTube player.
class WebAudioStream {
  const WebAudioStream({
    required this.tag,
    required this.url,
    required this.container,
    required this.mimeType,
    required this.bitrate,
    required this.bytes,
    required this.trackId,
    required this.trackName,
    required this.isDefault,
  });

  final int tag;
  final Uri url;
  final String container;
  final String mimeType;
  final int bitrate;
  final int bytes;
  final String trackId;
  final String trackName;
  final bool isDefault;

  WebAudioStream copyWithUrl(Uri value) => WebAudioStream(
    tag: tag,
    url: value,
    container: container,
    mimeType: mimeType,
    bitrate: bitrate,
    bytes: bytes,
    trackId: trackId,
    trackName: trackName,
    isDefault: isDefault,
  );
}

/// One video-only stream returned by the embedded YouTube player.
class WebVideoStream {
  const WebVideoStream({
    required this.tag,
    required this.url,
    required this.container,
    required this.mimeType,
    required this.bitrate,
    required this.bytes,
    required this.height,
  });

  final int tag;
  final Uri url;
  final String container;
  final String mimeType;
  final int bitrate;
  final int bytes;
  final int height;

  WebVideoStream copyWithUrl(Uri value) => WebVideoStream(
    tag: tag,
    url: value,
    container: container,
    mimeType: mimeType,
    bitrate: bitrate,
    bytes: bytes,
    height: height,
  );
}

/// Playable streams extracted from the embedded player response.
class WebManifest {
  const WebManifest({required this.audio, required this.video});

  final List<WebAudioStream> audio;
  final List<WebVideoStream> video;

  WebAudioStream selectAudio(String trackId, {required bool mp4Only}) {
    final matching = audio.where((s) => s.trackId == trackId).toList();
    if (matching.isEmpty) {
      throw StateError(
        'Wybrana ścieżka nie jest już dostępna. Odśwież listę języków.',
      );
    }
    final mp4 = matching.where((s) => s.container == 'mp4').toList();
    if (mp4.isEmpty && mp4Only) {
      throw StateError(
        'Ta ścieżka nie ma strumienia MP4 obsługiwanego przez iOS/macOS. '
        'Wybierz inny język lub film.',
      );
    }
    final candidates = mp4.isNotEmpty ? mp4 : matching;
    candidates.sort((a, b) {
      final da = (a.bitrate - 128000).abs();
      final db = (b.bitrate - 128000).abs();
      if (da != db) return da.compareTo(db);
      return b.bitrate.compareTo(a.bitrate);
    });
    return candidates.first;
  }

  WebVideoStream? selectVideo({int maxHeight = 720}) {
    final candidates = video.where((s) => s.height <= maxHeight).toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    return candidates.firstOrNull;
  }
}

/// The embedded player refused to expose a playable manifest.
class WebEmbeddedException implements Exception {
  const WebEmbeddedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Fetches media URLs through YouTube's embedded web player.
///
/// Unlike the native Android/iOS clients, `WEB_EMBEDDED_PLAYER` exposes direct
/// HTTPS URLs for every language track and does not stop serving after the
/// first megabyte. It needs the watch-page context (including its visitor ID
/// and cookies), the embed-page player context and YouTube's encrypted host
/// flags. Those are fetched lazily for each video and cached for a few minutes.
class WebEmbeddedClient {
  WebEmbeddedClient({
    HttpClient? client,
    this.challengeSolver,
    this.sessionTtl = const Duration(minutes: 10),
    this.manifestTtl = const Duration(minutes: 2),
  }) : _client = client ?? HttpClient(),
       _ownsClient = client == null {
    _client.connectionTimeout = const Duration(seconds: 30);
    _client.idleTimeout = const Duration(seconds: 15);
    _client.autoUncompress = true;
  }

  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/138.0.0.0 Safari/537.36';
  static const _defaultCookies = 'PREF=hl=en&tz=UTC; SOCS=CAI; GPS=1';

  final HttpClient _client;
  final bool _ownsClient;
  final NChallengeSolver? challengeSolver;
  final Duration sessionTtl;
  final Duration manifestTtl;
  final Map<String, _Session> _sessions = {};
  final Map<String, _CachedManifest> _manifests = {};

  bool get canUnlock => challengeSolver != null;

  /// Returns the manifest for [videoId], refreshing it when needed.
  Future<WebManifest> manifest(String videoId, {bool refresh = false}) async {
    final cached = _manifests[videoId];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.created) < manifestTtl) {
      return cached.manifest;
    }
    final hadSession = _sessions.containsKey(videoId);
    try {
      // A manifest refresh only needs a new player response. Re-downloading the
      // 2.5 MB player script and re-running the solver is slow and can trip
      // YouTube's throttling, so reuse the cached session/player JS.
      final cached = _sessions[videoId];
      final session =
          cached != null &&
              DateTime.now().difference(cached.created) < sessionTtl
          ? cached
          : await _session(videoId, refresh: refresh);
      final parsed = await _fetch(videoId, session);
      _manifests[videoId] = _CachedManifest(parsed, DateTime.now());
      return parsed;
    } catch (_) {
      // A visitor/context can go stale before its nominal TTL.
      _sessions.remove(videoId);
      _manifests.remove(videoId);
      if (!hadSession) rethrow;
      try {
        final session = await _session(videoId, refresh: true);
        final parsed = await _fetch(videoId, session);
        _manifests[videoId] = _CachedManifest(parsed, DateTime.now());
        return parsed;
      } catch (_) {
        _sessions.remove(videoId);
        _manifests.remove(videoId);
        rethrow;
      }
    }
  }

  /// Extracts the first `ytcfg.set({...});` object from a YouTube page.
  static Map<String, dynamic>? extractConfig(String html) {
    const marker = 'ytcfg.set({';
    var start = html.indexOf(marker);
    while (start >= 0) {
      final i = start + marker.length - 1;
      var depth = 0;
      var inString = false;
      var escape = false;
      var end = -1;
      for (var j = i; j < html.length; j++) {
        final c = html[j];
        if (inString) {
          if (escape) {
            escape = false;
          } else if (c == r'\') {
            escape = true;
          } else if (c == '"') {
            inString = false;
          }
        } else if (c == '"') {
          inString = true;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) {
            end = j + 1;
            break;
          }
        }
      }
      if (end > 0) {
        try {
          final decoded = jsonDecode(html.substring(i, end));
          if (decoded is Map<String, dynamic> &&
              decoded.containsKey('INNERTUBE_CONTEXT')) {
            return decoded;
          }
        } catch (_) {
          // Try the next occurrence.
        }
      }
      start = html.indexOf(marker, start + marker.length);
    }
    return null;
  }

  static WebManifest parsePlayerResponse(Map<String, dynamic> json) {
    final status = json['playabilityStatus'];
    final state = status is Map ? status['status'] : null;
    if (state != 'OK') {
      final reason = status is Map ? status['reason'] : null;
      throw WebEmbeddedException(
        reason is String && reason.isNotEmpty
            ? 'YouTube: $reason'
            : 'YouTube nie udostępnił strumieni tego filmu.',
      );
    }
    final streaming = json['streamingData'];
    if (streaming is! Map) {
      throw const WebEmbeddedException(
        'YouTube nie zwrócił danych strumieniowania.',
      );
    }
    final audio = <WebAudioStream>[];
    final video = <WebVideoStream>[];
    final formats = (streaming['adaptiveFormats'] as List?) ?? const [];
    for (final raw in formats) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final url = Uri.tryParse(m['url'] as String? ?? '');
      final mime = m['mimeType'] as String? ?? '';
      if (url == null || !url.hasScheme) continue;
      final container = _container(mime);
      final tag = _int(m['itag']);
      final bitrate = _int(m['bitrate'] ?? m['averageBitrate']);
      final bytes = _int(m['contentLength']);
      if (tag <= 0 || bytes <= 0) continue;
      if (mime.startsWith('audio/')) {
        final track = m['audioTrack'] is Map
            ? Map<String, dynamic>.from(m['audioTrack'] as Map)
            : const <String, dynamic>{};
        final id = (track['id'] as String?)?.trim();
        final baseId = id == null || id.isEmpty ? '' : id.split('.').first;
        final name = (track['displayName'] as String?)?.trim();
        audio.add(
          WebAudioStream(
            tag: tag,
            url: url,
            container: container,
            mimeType: _mimeType(container, video: false),
            bitrate: bitrate,
            bytes: bytes,
            trackId: baseId.isEmpty ? 'und' : baseId,
            trackName: name == null || name.isEmpty
                ? 'Język nieoznaczony'
                : name,
            isDefault: track['audioIsDefault'] == true,
          ),
        );
      } else if (mime.startsWith('video/') && container == 'mp4') {
        video.add(
          WebVideoStream(
            tag: tag,
            url: url,
            container: container,
            mimeType: _mimeType(container, video: true),
            bitrate: bitrate,
            bytes: bytes,
            height: _int(m['height']),
          ),
        );
      }
    }
    if (audio.isEmpty) {
      throw const WebEmbeddedException(
        'Brak ścieżek audio w odpowiedzi YouTube.',
      );
    }
    return WebManifest(audio: audio, video: video);
  }

  Future<_Session> _session(String videoId, {required bool refresh}) async {
    final cached = _sessions[videoId];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.created) < sessionTtl) {
      return cached;
    }
    final jar = _CookieJar();
    final watchHtml = await _get(
      'https://www.youtube.com/watch?v=$videoId'
      '&bpctr=9999999999&has_verified=1&hl=en',
      jar,
    );
    final watch = extractConfig(watchHtml);
    if (watch == null) {
      throw const WebEmbeddedException(
        'Nie udało się odczytać konfiguracji strony YouTube.',
      );
    }
    final embedHtml = await _get(
      'https://www.youtube.com/embed/$videoId?html5=1',
      jar,
    );
    final embed = extractConfig(embedHtml);
    if (embed == null) {
      throw const WebEmbeddedException(
        'Nie udało się odczytać konfiguracji odtwarzacza osadzonego.',
      );
    }
    final embedContext = embed['INNERTUBE_CONTEXT'];
    final contexts = embed['WEB_PLAYER_CONTEXT_CONFIGS'];
    final embedded = contexts is Map
        ? contexts['WEB_PLAYER_CONTEXT_CONFIG_ID_EMBEDDED_PLAYER']
        : null;
    final apiKey = embed['INNERTUBE_API_KEY'];
    final version = embed['INNERTUBE_CONTEXT_CLIENT_VERSION'];
    if (embedded is! Map || apiKey is! String || version is! String) {
      throw const WebEmbeddedException(
        'Konfiguracja odtwarzacza osadzonego jest niepełna.',
      );
    }
    final watchContext = watch['INNERTUBE_CONTEXT'];
    if (watchContext is! Map) {
      throw const WebEmbeddedException('Brak kontekstu strony YouTube.');
    }
    if (embedContext is! Map) {
      throw const WebEmbeddedException(
        'Brak kontekstu odtwarzacza osadzonego.',
      );
    }
    final context = Map<String, dynamic>.from(embedContext);
    final watchClient = watchContext['client'];
    final embedClient = context['client'];
    if (watchClient is! Map || embedClient is! Map) {
      throw const WebEmbeddedException('Brak klienta w kontekście YouTube.');
    }
    final watchVisitor = watchClient['visitorData'];
    final thirdParty = Map<String, dynamic>.from(
      context['thirdParty'] is Map ? context['thirdParty'] as Map : const {},
    )..['embedUrl'] = 'https://www.reddit.com/';
    context['thirdParty'] = thirdParty;
    final clientMap = Map<String, dynamic>.from(embedClient);
    if (watchVisitor is String && watchVisitor.isNotEmpty) {
      clientMap['visitorData'] = watchVisitor;
    }
    clientMap['originalUrl'] = 'https://www.youtube.com/embed/$videoId?html5=1';
    clientMap.putIfAbsent('utcOffsetMinutes', () => 0);
    context['client'] = clientMap;
    final visitor = clientMap['visitorData'] as String? ?? '';
    var signatureTimestamp = _int(watch['STS']);
    var playerUrl = '';
    var playerJs = '';
    final jsPath = watch['PLAYER_JS_URL'];
    if (jsPath is String && jsPath.isNotEmpty) {
      playerUrl = jsPath.startsWith('http')
          ? jsPath
          : 'https://www.youtube.com$jsPath';
      try {
        playerJs = await _get(playerUrl, jar);
        final match = RegExp(
          r'(?:signatureTimestamp|sts)\s*:\s*([0-9]{5})',
        ).firstMatch(playerJs);
        if (match != null) {
          signatureTimestamp =
              int.tryParse(match.group(1)!) ?? signatureTimestamp;
        }
      } catch (_) {
        // Without player JS the media URLs cannot be unlocked; the caller
        // falls back to the native client.
      }
    }
    final session = _Session(
      context: context,
      apiUrl:
          'https://www.youtube.com/youtubei/v1/player?prettyPrint=false'
          '&key=$apiKey',
      encryptedHostFlags: embedded['encryptedHostFlags'] as String?,
      signatureTimestamp: signatureTimestamp,
      cookies: jar.header,
      visitor: visitor,
      version: version,
      playerUrl: playerUrl,
      playerJs: playerJs,
      created: DateTime.now(),
    );
    _sessions[videoId] = session;
    return session;
  }

  Future<String> _get(String url, _CookieJar jar) async {
    final req = await _client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.userAgentHeader, userAgent);
    req.headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    );
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'en-us,en;q=0.5');
    req.headers.set('Sec-Fetch-Mode', 'navigate');
    req.headers.set('Referer', 'https://www.reddit.com/');
    req.headers.set(HttpHeaders.cookieHeader, _cookies(jar));
    final res = await req.close();
    jar.absorb(res);
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != HttpStatus.ok) {
      throw WebEmbeddedException(
        'YouTube odpowiedział ${res.statusCode} przy pobieraniu strony.',
      );
    }
    return text;
  }

  Future<WebManifest> _fetch(String videoId, _Session session) async {
    final body = <String, dynamic>{
      'context': session.context,
      'videoId': videoId,
      'playbackContext': {
        'contentPlaybackContext': {
          'html5Preference': 'HTML5_PREF_WANTS',
          if (session.signatureTimestamp > 0)
            'signatureTimestamp': session.signatureTimestamp,
          if (session.encryptedHostFlags != null)
            'encryptedHostFlags': session.encryptedHostFlags,
        },
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    };
    final req = await _client.postUrl(Uri.parse(session.apiUrl));
    req.headers.set('X-Youtube-Client-Name', '56');
    req.headers.set('X-Youtube-Client-Version', session.version);
    if (session.visitor.isNotEmpty) {
      req.headers.set('X-Goog-Visitor-Id', session.visitor);
    }
    req.headers.set(HttpHeaders.userAgentHeader, userAgent);
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'en-us,en;q=0.5');
    req.headers.set('Origin', 'https://www.youtube.com');
    req.headers.set('Sec-Fetch-Mode', 'navigate');
    req.headers.set(HttpHeaders.cookieHeader, _cookieHeader(session.cookies));
    req.headers.contentType = ContentType.json;
    final encoded = jsonEncode(body);
    req.contentLength = utf8.encode(encoded).length;
    req.write(encoded);
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != HttpStatus.ok) {
      throw WebEmbeddedException(
        'YouTube odpowiedział ${res.statusCode} przy pobieraniu strumieni.',
      );
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const WebEmbeddedException('Nieoczekiwana odpowiedź YouTube.');
    }
    final manifest = parsePlayerResponse(decoded);
    return _solveChallenges(manifest, session);
  }

  Future<WebManifest> _solveChallenges(
    WebManifest manifest,
    _Session session,
  ) async {
    final solver = challengeSolver;
    if (solver == null || session.playerJs.isEmpty) return manifest;
    final challenges = <String>{};
    void addChallenge(Uri url) {
      final n = url.queryParameters['n'];
      if (n != null && n.isNotEmpty) challenges.add(n);
    }

    for (final s in manifest.audio) {
      addChallenge(s.url);
    }
    for (final s in manifest.video) {
      addChallenge(s.url);
    }
    final solved = <String, String>{};
    for (final challenge in challenges) {
      final value = await solver.solveN(
        playerUrl: session.playerUrl,
        playerJs: session.playerJs,
        challenge: challenge,
      );
      if (value == null || value.isEmpty) {
        throw const WebEmbeddedException(
          'Nie udało się rozwiązać zabezpieczenia YouTube.',
        );
      }
      solved[challenge] = value;
    }
    Uri unlock(Uri url) {
      final n = url.queryParameters['n'];
      if (n == null || !solved.containsKey(n)) return url;
      return url.replace(
        queryParameters: {...url.queryParameters, 'n': solved[n]!},
      );
    }

    return WebManifest(
      audio: manifest.audio.map((s) => s.copyWithUrl(unlock(s.url))).toList(),
      video: manifest.video.map((s) => s.copyWithUrl(unlock(s.url))).toList(),
    );
  }

  String _cookies(_CookieJar jar) =>
      jar.header.isEmpty ? _defaultCookies : '$_defaultCookies; ${jar.header}';

  String _cookieHeader(String cookies) =>
      cookies.isEmpty ? _defaultCookies : '$_defaultCookies; $cookies';

  static String _container(String mime) {
    final lower = mime.toLowerCase();
    if (lower.startsWith('audio/mp4') || lower.startsWith('video/mp4')) {
      return 'mp4';
    }
    if (lower.startsWith('audio/webm') || lower.startsWith('video/webm')) {
      return 'webm';
    }
    if (lower.startsWith('audio/3gpp') || lower.startsWith('video/3gpp')) {
      return '3gpp';
    }
    return 'bin';
  }

  static String _mimeType(String container, {required bool video}) =>
      switch (container) {
        'mp4' => video ? 'video/mp4' : 'audio/mp4',
        'webm' => video ? 'video/webm' : 'audio/webm',
        '3gpp' => video ? 'video/3gpp' : 'audio/3gpp',
        _ => 'application/octet-stream',
      };

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  void close() {
    _sessions.clear();
    _manifests.clear();
    if (_ownsClient) _client.close(force: true);
  }
}

class _Session {
  const _Session({
    required this.context,
    required this.apiUrl,
    required this.encryptedHostFlags,
    required this.signatureTimestamp,
    required this.cookies,
    required this.visitor,
    required this.version,
    required this.playerUrl,
    required this.playerJs,
    required this.created,
  });

  final Map<String, dynamic> context;
  final String apiUrl;
  final String? encryptedHostFlags;
  final int signatureTimestamp;
  final String cookies;
  final String visitor;
  final String version;
  final String playerUrl;
  final String playerJs;
  final DateTime created;
}

class _CachedManifest {
  const _CachedManifest(this.manifest, this.created);
  final WebManifest manifest;
  final DateTime created;
}

class _CookieJar {
  final Map<String, String> _values = {};

  void absorb(HttpClientResponse response) {
    final raw = response.headers[HttpHeaders.setCookieHeader];
    if (raw == null) return;
    for (final line in raw) {
      final pair = line.split(';').first;
      final at = pair.indexOf('=');
      if (at <= 0) continue;
      _values[pair.substring(0, at).trim()] = pair.substring(at + 1).trim();
    }
  }

  String get header =>
      _values.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

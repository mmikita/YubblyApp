import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'audio_downloader.dart';
import 'models.dart';
import 'stream_proxy.dart';
import 'web_embedded.dart';

class VideoDetails {
  final VideoItem video;
  final List<AudioChoice> tracks;
  const VideoDetails(this.video, this.tracks);
}

/// Metadata and location of one completed offline audio download.
class DownloadedAudio {
  const DownloadedAudio({
    required this.file,
    required this.trackId,
    required this.label,
    required this.isDefault,
    required this.container,
    required this.mimeType,
    required this.bytes,
    required this.bitrate,
  });

  final File file;
  final String trackId;
  final String label;
  final bool isDefault;
  final String container;
  final String mimeType;
  final int bytes;
  final int bitrate;
}

class YoutubeRepository {
  YoutubeRepository({this.cacheDirectory, NChallengeSolver? challengeSolver})
    : _web = WebEmbeddedClient(challengeSolver: challengeSolver);

  final YoutubeExplode _yt = YoutubeExplode();
  final WebEmbeddedClient _web;

  /// Used for full-track offline downloads. Kept separate from the proxy's
  /// client so a cancelled download never disturbs live playback.
  final HttpClient _downloadClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..idleTimeout = const Duration(seconds: 15);

  /// Where [StreamProxy] stores its segment cache. Defaults to a subdirectory
  /// of the platform temp directory; injectable for tests and tooling.
  final Directory? cacheDirectory;

  /// Loopback server that turns YouTube's one-shot media URLs into something
  /// AVFoundation and ExoPlayer can stream. Started lazily, `null` where the
  /// platform has no writable temp directory.
  StreamProxy? _proxy;

  /// Set when the proxy cannot be created, so raw URLs are used instead.
  bool _proxyUnavailable = false;

  /// Number of manifests minted for media URLs; diagnostics only.
  int mintedManifests = 0;

  VideoItem _item(Video v) => VideoItem(
    id: v.id.value,
    title: v.title,
    channelName: v.author,
    channelUrl: 'https://www.youtube.com/channel/${v.channelId.value}',
    durationMs: v.duration?.inMilliseconds ?? 0,
  );

  Future<VideoItem> video(String id) async =>
      _item(await _yt.videos.get(id).timeout(const Duration(seconds: 30)));

  Future<StreamManifest> _manifest(String id) =>
      _yt.videos.streams.getManifest(id).timeout(const Duration(seconds: 45));

  /// Direct multi-language URLs from the embedded web player.
  ///
  /// Returns `null` when the embedded player is unavailable or the n-signature
  /// solver is not configured; callers then use the native client fallback.
  Future<WebManifest?> _webManifest(String id) async {
    if (!_web.canUnlock) return null;
    try {
      return await _web.manifest(id).timeout(const Duration(seconds: 90));
    } catch (_) {
      return null;
    }
  }

  List<AudioOnlyStreamInfo> _audio(StreamManifest m) =>
      m.audioOnly.where((s) => s.fragments.isEmpty).toList();
  String _key(AudioOnlyStreamInfo s) =>
      (s.audioTrack?.id ?? 'und').split('.').first;

  Future<VideoDetails> inspect(String id, {bool mp4Only = false}) async {
    final v = await video(id);
    final web = await _webManifest(id);
    final choices = <String, AudioChoice>{};
    if (web != null) {
      for (final s in web.audio) {
        if (mp4Only && s.container != 'mp4') continue;
        choices.putIfAbsent(
          s.trackId,
          () => AudioChoice(s.trackId, s.trackName, s.isDefault),
        );
      }
    } else {
      final manifest = await _manifest(id);
      for (final s in _audio(manifest)) {
        if (mp4Only && s.container.name != 'mp4') continue;
        final t = s.audioTrack;
        choices[_key(s)] = AudioChoice(
          _key(s),
          t?.displayName ?? 'Język nieoznaczony',
          t?.audioIsDefault ?? false,
        );
      }
    }
    final tracks = choices.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return VideoDetails(v, tracks);
  }

  AudioOnlyStreamInfo _select(
    StreamManifest m,
    String id, {
    required bool mp4Only,
  }) {
    final options = _audio(m).where((s) => _key(s) == id).toList()
      ..sort(
        (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
      );
    if (options.isEmpty) {
      throw StateError(
        'Wybrana ścieżka nie jest już dostępna. Odśwież listę języków.',
      );
    }
    // Prefer an ordinary MP4 audio stream: natively decodable on Android and
    // the only container AVFoundation can play reliably on iOS/macOS.
    final mp4 = options.where((s) => s.container.name == 'mp4').firstOrNull;
    if (mp4 != null) return mp4;
    if (mp4Only) {
      throw StateError(
        'Ta ścieżka nie ma strumienia MP4 obsługiwanego przez iOS/macOS. '
        'Wybierz inny język lub film.',
      );
    }
    return options.first;
  }

  Future<Map<String, dynamic>> streams(
    String id,
    String a,
    String b, {
    required bool video,
    bool mp4Only = false,
  }) async {
    if (a == b) throw StateError('Wybierz dwa różne języki.');
    final web = await _webManifest(id);
    if (web != null) {
      return _streamsWeb(id, web, a, b, video: video, mp4Only: mp4Only);
    }
    // Fresh, independent manifests: Android client URLs can be single-session-bound.
    final streamA = _select(await _manifest(id), a, mp4Only: mp4Only);
    final streamB = _select(await _manifest(id), b, mp4Only: mp4Only);
    VideoOnlyStreamInfo? videoStream;
    if (video) {
      final mv = await _manifest(id);
      final candidates =
          mv.videoOnly
              .where(
                (s) =>
                    s.fragments.isEmpty &&
                    s.container.name == 'mp4' &&
                    s.videoResolution.height <= 720,
              )
              .toList()
            ..sort(
              (a, b) =>
                  b.videoResolution.height.compareTo(a.videoResolution.height),
            );
      videoStream = candidates.firstOrNull;
      if (videoStream == null) {
        throw StateError(
          'Brak zgodnego strumienia obrazu. Wyłącz obraz i uruchom samo audio.',
        );
      }
    }
    final proxy = await _ensureProxy();
    if (proxy == null) {
      return {
        'urlA': streamA.url.toString(),
        'urlB': streamB.url.toString(),
        'videoUrl': videoStream?.url.toString(),
      };
    }
    await proxy.release();
    final urlA = await proxy.register(
      ProxyTrack(
        length: streamA.size.totalBytes,
        mimeType: _mimeType(streamA.container, video: false),
        mint: () => _freshUrl(id, a, streamA.tag, mp4Only: mp4Only),
      ),
    );
    final urlB = await proxy.register(
      ProxyTrack(
        length: streamB.size.totalBytes,
        mimeType: _mimeType(streamB.container, video: false),
        mint: () => _freshUrl(id, b, streamB.tag, mp4Only: mp4Only),
      ),
    );
    String? videoUrl;
    final chosenVideo = videoStream;
    if (chosenVideo != null) {
      videoUrl = await proxy.register(
        ProxyTrack(
          length: chosenVideo.size.totalBytes,
          mimeType: _mimeType(chosenVideo.container, video: true),
          mint: () => _freshVideoUrl(id, chosenVideo.tag),
        ),
      );
    }
    return {'urlA': urlA, 'urlB': urlB, 'videoUrl': videoUrl};
  }

  Future<Map<String, dynamic>> _streamsWeb(
    String id,
    WebManifest manifest,
    String a,
    String b, {
    required bool video,
    required bool mp4Only,
  }) async {
    final streamA = manifest.selectAudio(a, mp4Only: mp4Only);
    final streamB = manifest.selectAudio(b, mp4Only: mp4Only);
    final chosenVideo = video ? manifest.selectVideo() : null;
    if (video && chosenVideo == null) {
      throw StateError(
        'Brak zgodnego strumienia obrazu. Wyłącz obraz i uruchom samo audio.',
      );
    }
    final proxy = await _ensureProxy();
    if (proxy == null) {
      return {
        'urlA': streamA.url.toString(),
        'urlB': streamB.url.toString(),
        'videoUrl': chosenVideo?.url.toString(),
      };
    }
    await proxy.release();
    final urlA = await proxy.register(
      ProxyTrack(
        length: streamA.bytes,
        mimeType: streamA.mimeType,
        mint: () => _freshWebAudio(id, a, streamA.tag, mp4Only: mp4Only),
        refreshMint: () =>
            _freshWebAudio(id, a, streamA.tag, mp4Only: mp4Only, refresh: true),
      ),
    );
    final urlB = await proxy.register(
      ProxyTrack(
        length: streamB.bytes,
        mimeType: streamB.mimeType,
        mint: () => _freshWebAudio(id, b, streamB.tag, mp4Only: mp4Only),
        refreshMint: () =>
            _freshWebAudio(id, b, streamB.tag, mp4Only: mp4Only, refresh: true),
      ),
    );
    String? videoUrl;
    if (chosenVideo != null) {
      videoUrl = await proxy.register(
        ProxyTrack(
          length: chosenVideo.bytes,
          mimeType: chosenVideo.mimeType,
          mint: () => _freshWebVideo(id, chosenVideo.tag),
          refreshMint: () => _freshWebVideo(id, chosenVideo.tag, refresh: true),
        ),
      );
    }
    return {'urlA': urlA, 'urlB': urlB, 'videoUrl': videoUrl};
  }

  Future<Uri?> _freshWebAudio(
    String id,
    String language,
    int tag, {
    required bool mp4Only,
    bool refresh = false,
  }) async {
    try {
      final manifest = await _web.manifest(id, refresh: refresh);
      for (final s in manifest.audio) {
        if (s.trackId == language && s.tag == tag) return s.url;
      }
      return manifest.selectAudio(language, mp4Only: mp4Only).url;
    } catch (_) {
      return null;
    }
  }

  Future<Uri?> _freshWebVideo(
    String id,
    int tag, {
    bool refresh = false,
  }) async {
    try {
      final manifest = await _web.manifest(id, refresh: refresh);
      for (final s in manifest.video) {
        if (s.tag == tag) return s.url;
      }
      return manifest.selectVideo()?.url;
    } catch (_) {
      return null;
    }
  }

  ///
  /// Prefers an MP4/AAC variant because it is natively decodable by AVFoundation
  /// and ExoPlayer. The bitrate closest to 128 kbps is chosen when YouTube
  /// offers several variants. The returned [DownloadedAudio.file] is already
  /// complete; a `.part` file may remain after cancellation and is resumed by
  /// the next call.
  Future<DownloadedAudio> downloadAudio({
    required String videoId,
    required String trackId,
    required Directory directory,
    required bool mp4Only,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final web = await _webManifest(videoId);
    if (web != null) {
      return _downloadWeb(
        id: videoId,
        manifest: web,
        trackId: trackId,
        directory: directory,
        mp4Only: mp4Only,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    }
    final manifest = await _manifest(videoId);
    final stream = _selectForDownload(manifest, trackId, mp4Only: mp4Only);
    final extension = extensionFor(stream.container);
    final file = File('${directory.path}/${_fileSafe(trackId)}.$extension');
    final downloader = AudioDownloader(client: _downloadClient);
    await downloader.download(
      spec: AudioDownloadSpec(
        initialUrl: stream.url,
        totalBytes: stream.size.totalBytes,
      ),
      destination: file,
      mint: () => _freshUrl(videoId, trackId, stream.tag, mp4Only: mp4Only),
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    return DownloadedAudio(
      file: file,
      trackId: trackId,
      label: stream.audioTrack?.displayName ?? trackId,
      isDefault: stream.audioTrack?.audioIsDefault ?? false,
      container: stream.container.name,
      mimeType: _mimeType(stream.container, video: false),
      bytes: await file.length(),
      bitrate: stream.bitrate.bitsPerSecond,
    );
  }

  Future<DownloadedAudio> _downloadWeb({
    required String id,
    required WebManifest manifest,
    required String trackId,
    required Directory directory,
    required bool mp4Only,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final stream = manifest.selectAudio(trackId, mp4Only: mp4Only);
    final extension = _extensionForName(stream.container);
    final file = File('${directory.path}/${_fileSafe(trackId)}.$extension');
    final downloader = AudioDownloader(client: _downloadClient);
    await downloader.download(
      spec: AudioDownloadSpec(initialUrl: stream.url, totalBytes: stream.bytes),
      destination: file,
      mint: () => _freshWebAudio(id, trackId, stream.tag, mp4Only: mp4Only),
      refreshMint: () => _freshWebAudio(
        id,
        trackId,
        stream.tag,
        mp4Only: mp4Only,
        refresh: true,
      ),
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    return DownloadedAudio(
      file: file,
      trackId: trackId,
      label: stream.trackName,
      isDefault: stream.isDefault,
      container: stream.container,
      mimeType: stream.mimeType,
      bytes: await file.length(),
      bitrate: stream.bitrate,
    );
  }

  /// Chooses the variant closest to 128 kbps, preferring MP4 when available.
  AudioOnlyStreamInfo _selectForDownload(
    StreamManifest manifest,
    String trackId, {
    required bool mp4Only,
  }) {
    final matching = _audio(manifest).where((s) => _key(s) == trackId).toList();
    if (matching.isEmpty) {
      throw StateError(
        'Wybrana ścieżka nie jest już dostępna. Odśwież listę języków.',
      );
    }
    final mp4 = matching.where((s) => s.container.name == 'mp4').toList();
    if (mp4.isEmpty && mp4Only) {
      throw StateError(
        'Ta ścieżka nie ma strumienia MP4 obsługiwanego przez iOS/macOS. '
        'Wybierz inny język lub film.',
      );
    }
    final candidates = mp4.isNotEmpty ? mp4 : matching;
    candidates.sort((a, b) {
      final distanceA = (a.bitrate.bitsPerSecond - 128000).abs();
      final distanceB = (b.bitrate.bitsPerSecond - 128000).abs();
      if (distanceA != distanceB) return distanceA.compareTo(distanceB);
      return b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond);
    });
    return candidates.first;
  }

  /// File extension matching the YouTube container.
  static String extensionFor(StreamContainer container) =>
      switch (container.name) {
        'mp4' => 'm4a',
        'webm' => 'webm',
        '3gpp' => '3gp',
        _ => 'bin',
      };

  static String _fileSafe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static String _extensionForName(String container) => switch (container) {
    'mp4' => 'm4a',
    'webm' => 'webm',
    '3gpp' => '3gp',
    _ => 'bin',
  };

  static String _mimeType(StreamContainer container, {required bool video}) =>
      switch (container.name) {
        'mp4' => video ? 'video/mp4' : 'audio/mp4',
        'webm' => video ? 'video/webm' : 'audio/webm',
        '3gpp' => video ? 'video/3gpp' : 'audio/3gpp',
        _ => 'application/octet-stream',
      };

  /// Creates the loopback proxy on first use.
  Future<StreamProxy?> _ensureProxy() async {
    if (_proxy != null || _proxyUnavailable) return _proxy;
    try {
      final dir =
          cacheDirectory ??
          Directory('${(await getTemporaryDirectory()).path}/yubbly_streams');
      final proxy = StreamProxy(cacheDir: dir);
      await proxy.start();
      return _proxy = proxy;
    } catch (_) {
      // No temp directory (e.g. a plain Dart VM): fall back to raw URLs.
      _proxyUnavailable = true;
      return null;
    }
  }

  /// Drops cached media segments of the previous session.
  Future<void> releaseStreams() async => _proxy?.release();

  /// A manifest used only for minting media URLs.
  ///
  /// Uses the watch page: `getManifest(requireWatchPage: false)` currently
  /// returns signed URLs that answer HTTP 403 even for the first byte. The
  /// watch page costs more per segment, but its URLs actually serve ranges.
  Future<StreamManifest> _mintManifest(String id) async {
    mintedManifests++;
    return _manifest(id);
  }

  /// Mints a fresh URL for one language track.
  Future<Uri?> _freshUrl(
    String id,
    String language,
    int tag, {
    required bool mp4Only,
  }) async {
    final manifest = await _mintManifest(id);
    final same = _audio(manifest).where((s) => _key(s) == language);
    for (final stream in same) {
      if (stream.tag == tag) return stream.url;
    }
    try {
      return _select(manifest, language, mp4Only: mp4Only).url;
    } on StateError {
      return null;
    }
  }

  /// Mints a fresh URL for the video stream chosen when the session started.
  Future<Uri?> _freshVideoUrl(String id, int tag) async {
    final manifest = await _mintManifest(id);
    for (final stream in manifest.videoOnly) {
      if (stream.tag == tag && stream.fragments.isEmpty) return stream.url;
    }
    return null;
  }

  Future<ChannelItem> channel(String input) async {
    final u = Uri.tryParse(input.trim());
    if (u == null ||
        !['https', 'http'].contains(u.scheme) ||
        !['youtube.com', 'www.youtube.com', 'm.youtube.com'].contains(u.host)) {
      throw const FormatException('Wklej adres kanału YouTube.');
    }
    final id = videoIdFromInput(input);
    if (id != null) {
      final v = await video(id);
      return ChannelItem(v.channelName, v.channelUrl);
    }
    final parts = u.pathSegments;
    Channel c;
    if (parts.isNotEmpty && parts.first.startsWith('@')) {
      c = await _yt.channels
          .getByHandle(parts.first)
          .timeout(const Duration(seconds: 30));
    } else if (parts.length >= 2 && parts.first == 'channel') {
      c = await _yt.channels.get(parts[1]).timeout(const Duration(seconds: 30));
    } else if (parts.length >= 2 && parts.first == 'user') {
      c = await _yt.channels
          .getByUsername(parts[1])
          .timeout(const Duration(seconds: 30));
    } else {
      throw const FormatException('Użyj adresu /@nazwa lub /channel/ID.');
    }
    return ChannelItem(
      c.title,
      'https://www.youtube.com/channel/${c.id.value}',
    );
  }

  Future<ChannelUploadsList> uploads(ChannelItem c) async {
    final resolved = await channel(c.url);
    final id = Uri.parse(resolved.url).pathSegments.last;
    return _yt.channels
        .getUploadsFromPage(id)
        .timeout(const Duration(seconds: 30));
  }

  List<VideoItem> items(Iterable<Video> videos) => videos.map(_item).toList();
  void close() {
    _proxy?.close();
    _proxy = null;
    _web.close();
    _downloadClient.close(force: true);
    _yt.close();
  }
}

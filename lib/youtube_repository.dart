import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'models.dart';
import 'stream_proxy.dart';

class VideoDetails {
  final VideoItem video;
  final List<AudioChoice> tracks;
  const VideoDetails(this.video, this.tracks);
}

class YoutubeRepository {
  YoutubeRepository({this.cacheDirectory});

  final YoutubeExplode _yt = YoutubeExplode();

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

  List<AudioOnlyStreamInfo> _audio(StreamManifest m) =>
      m.audioOnly.where((s) => s.fragments.isEmpty).toList();
  String _key(AudioOnlyStreamInfo s) => s.audioTrack?.id ?? 'und';

  Future<VideoDetails> inspect(String id, {bool mp4Only = false}) async {
    final v = await video(id);
    final manifest = await _manifest(id);
    final choices = <String, AudioChoice>{};
    for (final s in _audio(manifest)) {
      if (mp4Only && s.container.name != 'mp4') continue;
      final t = s.audioTrack;
      choices[_key(s)] = AudioChoice(
        _key(s),
        t?.displayName ?? 'Język nieoznaczony',
        t?.audioIsDefault ?? false,
      );
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
  /// Skips the watch page when possible: the proxy needs a new URL roughly
  /// every megabyte, so this is the hot path and must stay cheap.
  Future<StreamManifest> _mintManifest(String id) async {
    mintedManifests++;
    try {
      return await _yt.videos.streams
          .getManifest(id, requireWatchPage: false)
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      return _manifest(id);
    }
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
    _yt.close();
  }
}

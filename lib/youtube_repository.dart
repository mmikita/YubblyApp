import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'models.dart';

class VideoDetails {
  final VideoItem video;
  final List<AudioChoice> tracks;
  const VideoDetails(this.video, this.tracks);
}

class YoutubeRepository {
  final YoutubeExplode _yt = YoutubeExplode();

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
    final ma = await _manifest(id);
    final mb = await _manifest(id);
    String? videoUrl;
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
      videoUrl = candidates.firstOrNull?.url.toString();
      if (videoUrl == null) {
        throw StateError(
          'Brak zgodnego strumienia obrazu. Wyłącz obraz i uruchom samo audio.',
        );
      }
    }
    return {
      'urlA': _select(ma, a, mp4Only: mp4Only).url.toString(),
      'urlB': _select(mb, b, mp4Only: mp4Only).url.toString(),
      'videoUrl': videoUrl,
    };
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
  void close() => _yt.close();
}

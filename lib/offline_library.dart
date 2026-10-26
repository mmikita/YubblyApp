import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// One downloaded language track belonging to an [OfflineAlbum].
class OfflineTrack {
  const OfflineTrack({
    required this.trackId,
    required this.label,
    required this.fileName,
    required this.bytes,
    required this.bitrate,
    required this.container,
    required this.downloadedAtMs,
    this.isDefault = false,
  });

  final String trackId;
  final String label;

  /// File name relative to the album directory. Kept relative so the library
  /// keeps working when the app container moves between launches.
  final String fileName;
  final int bytes;
  final int bitrate;
  final String container;
  final int downloadedAtMs;
  final bool isDefault;

  AudioChoice get choice => AudioChoice(trackId, label, isDefault);

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'label': label,
    'fileName': fileName,
    'bytes': bytes,
    'bitrate': bitrate,
    'container': container,
    'downloadedAtMs': downloadedAtMs,
    'isDefault': isDefault,
  };

  factory OfflineTrack.fromJson(Map<String, dynamic> j) => OfflineTrack(
    trackId: j['trackId'] as String,
    label: j['label'] as String? ?? j['trackId'] as String,
    fileName: j['fileName'] as String,
    bytes: (j['bytes'] as num?)?.toInt() ?? 0,
    bitrate: (j['bitrate'] as num?)?.toInt() ?? 0,
    container: j['container'] as String? ?? 'mp4',
    downloadedAtMs: (j['downloadedAtMs'] as num?)?.toInt() ?? 0,
    isDefault: j['isDefault'] == true,
  );
}

/// A video and all of its downloaded language tracks.
class OfflineAlbum {
  const OfflineAlbum({
    required this.video,
    required this.tracks,
    required this.updatedAtMs,
  });

  final VideoItem video;
  final Map<String, OfflineTrack> tracks;
  final int updatedAtMs;

  List<OfflineTrack> get trackList {
    final list = tracks.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return list;
  }

  int get totalBytes => tracks.values.fold(0, (sum, t) => sum + t.bytes);
  bool hasTrack(String id) => tracks.containsKey(id);
  bool hasPair(String a, String b) => hasTrack(a) && hasTrack(b) && a != b;
  OfflineTrack? track(String id) => tracks[id];

  Map<String, dynamic> toJson() => {
    'video': video.toJson(),
    'tracks': tracks.map((key, value) => MapEntry(key, value.toJson())),
    'updatedAtMs': updatedAtMs,
  };

  factory OfflineAlbum.fromJson(Map<String, dynamic> j) {
    final rawTracks = j['tracks'];
    if (rawTracks is! Map) {
      throw const FormatException('Brak ścieżek w albumie offline.');
    }
    final tracks = <String, OfflineTrack>{};
    for (final entry in rawTracks.entries) {
      if (entry.value is! Map) continue;
      final track = OfflineTrack.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
      tracks[track.trackId] = track;
    }
    return OfflineAlbum(
      video: VideoItem.fromJson(Map<String, dynamic>.from(j['video'] as Map)),
      tracks: tracks,
      updatedAtMs: (j['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Persistent library of downloaded audio albums.
///
/// The index lives next to the media files as `library.json`. Only metadata is
/// stored there; audio never leaves the app's support directory.
class OfflineLibrary {
  OfflineLibrary({Directory? rootDirectory}) : _root = rootDirectory;

  static const int schemaVersion = 1;

  Directory? _root;
  final Map<String, OfflineAlbum> _albums = {};
  bool _loaded = false;

  Directory get root {
    final root = _root;
    if (root == null) {
      throw StateError('Biblioteka offline nie została zainicjalizowana.');
    }
    return root;
  }

  Future<void> init() async {
    if (_loaded) return;
    _root ??= await _resolveRoot();
    await root.create(recursive: true);
    await _load();
    _loaded = true;
  }

  List<OfflineAlbum> get albums {
    final list = _albums.values.toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return List.unmodifiable(list);
  }

  OfflineAlbum? albumFor(String videoId) => _albums[videoId];

  Future<OfflineAlbum> ensureAlbum(VideoItem video) async {
    await init();
    final existing = _albums[video.id];
    final album = OfflineAlbum(
      video: video,
      tracks: existing?.tracks ?? const {},
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _albums[video.id] = album;
    await _save();
    return album;
  }

  Future<void> saveTrack(VideoItem video, OfflineTrack track) async {
    await init();
    final file = File('${_albumDir(video.id).path}/${track.fileName}');
    if (!await file.exists()) {
      throw StateError('Brak pobranego pliku audio dla ${track.label}.');
    }
    final existing = _albums[video.id];
    final tracks = <String, OfflineTrack>{...?existing?.tracks};
    tracks[track.trackId] = track;
    _albums[video.id] = OfflineAlbum(
      video: video,
      tracks: tracks,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _save();
  }

  Future<void> removeTrack(String videoId, String trackId) async {
    await init();
    final album = _albums[videoId];
    final track = album?.tracks[trackId];
    if (album == null || track == null) return;
    try {
      await File('${_albumDir(videoId).path}/${track.fileName}').delete();
    } catch (_) {}
    final tracks = {...album.tracks}..remove(trackId);
    if (tracks.isEmpty) {
      await removeAlbum(videoId);
      return;
    }
    _albums[videoId] = OfflineAlbum(
      video: album.video,
      tracks: tracks,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _save();
  }

  Future<void> removeAlbum(String videoId) async {
    await init();
    _albums.remove(videoId);
    try {
      await _albumDir(videoId).delete(recursive: true);
    } catch (_) {}
    await _save();
  }

  /// Removes an album that has no completed tracks from the index without
  /// deleting its directory. This preserves `.part` files for resume after a
  /// cancelled or failed first download.
  Future<void> discardEmptyAlbum(String videoId) async {
    await init();
    final album = _albums[videoId];
    if (album == null || album.tracks.isNotEmpty) return;
    _albums.remove(videoId);
    await _save();
  }

  /// Absolute path of a downloaded track, or `null` when the file is missing.
  String? pathFor(String videoId, String trackId) {
    final track = _albums[videoId]?.tracks[trackId];
    if (track == null) return null;
    final file = File('${_albumDir(videoId).path}/${track.fileName}');
    return file.existsSync() ? file.path : null;
  }

  File fileFor(String videoId, String trackId, String extension) =>
      File('${_albumDir(videoId).path}/${_safe(trackId)}.$extension');

  Directory _albumDir(String videoId) =>
      Directory('${root.path}/${_safe(videoId)}');

  Future<Directory> albumDirectory(String videoId) async {
    await init();
    final dir = _albumDir(videoId);
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _resolveRoot() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      // Unit tests and desktop tooling may not have the path_provider channel.
      return Directory.systemTemp.createTemp('yubbly_offline');
    }
  }

  File get _indexFile => File('${root.path}/library.json');

  Future<void> _load() async {
    _albums.clear();
    final file = _indexFile;
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['version'] != schemaVersion) return;
      final raw = decoded['albums'];
      if (raw is! List) return;
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          final album = OfflineAlbum.fromJson(Map<String, dynamic>.from(item));
          final dir = _albumDir(album.video.id);
          final valid = <String, OfflineTrack>{};
          for (final entry in album.tracks.entries) {
            final track = entry.value;
            if (!_safeFileName(track.fileName)) continue;
            final media = File('${dir.path}/${track.fileName}');
            if (!await media.exists()) continue;
            final length = await media.length();
            if (length <= 0) continue;
            valid[entry.key] = OfflineTrack(
              trackId: track.trackId,
              label: track.label,
              fileName: track.fileName,
              bytes: length,
              bitrate: track.bitrate,
              container: track.container,
              downloadedAtMs: track.downloadedAtMs,
              isDefault: track.isDefault,
            );
          }
          if (valid.isNotEmpty) {
            _albums[album.video.id] = OfflineAlbum(
              video: album.video,
              tracks: valid,
              updatedAtMs: album.updatedAtMs,
            );
          }
        } catch (_) {
          // Skip a malformed album, keep the rest of the library.
        }
      }
    } catch (_) {
      // A corrupt index must not prevent the app from starting.
      _albums.clear();
    }
  }

  Future<void> _save() async {
    await root.create(recursive: true);
    final data = jsonEncode({
      'version': schemaVersion,
      'albums': _albums.values.map((a) => a.toJson()).toList(),
    });
    final temp = File('${_indexFile.path}.tmp');
    await temp.writeAsString(data, flush: true);
    if (await _indexFile.exists()) await _indexFile.delete();
    await temp.rename(_indexFile.path);
  }

  static bool _safeFileName(String name) =>
      name.isNotEmpty &&
      !name.contains('/') &&
      !name.contains('\\') &&
      !name.contains('..');

  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yubbly_app/models.dart';
import 'package:yubbly_app/offline_library.dart';

void main() {
  const video = VideoItem(
    id: 'hAMa1nWM49A',
    title: 'Dwa języki. Jedna rozmowa.',
    channelName: 'Stand to Reason',
    durationMs: 600000,
  );
  late Directory root;
  late OfflineLibrary library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('yubbly_library');
    library = OfflineLibrary(rootDirectory: Directory('${root.path}/library'));
    await library.init();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<OfflineTrack> addTrack(
    String id,
    String label, {
    int bytes = 2048,
  }) async {
    final dir = await library.albumDirectory(video.id);
    final file = File('${dir.path}/$id.m4a');
    await file.writeAsBytes(List<int>.filled(bytes, 7));
    final track = OfflineTrack(
      trackId: id,
      label: label,
      fileName: '$id.m4a',
      bytes: bytes,
      bitrate: 128000,
      container: 'mp4',
      downloadedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await library.saveTrack(video, track);
    return track;
  }

  test('groups multiple languages under one video album', () async {
    await library.ensureAlbum(video);
    await addTrack('pl.4', 'Polski');
    await addTrack('en.4', 'English (original)');

    final album = library.albumFor(video.id)!;
    expect(album.video.title, video.title);
    expect(album.trackList.map((t) => t.label), [
      'English (original)',
      'Polski',
    ]);
    expect(album.hasPair('pl.4', 'en.4'), isTrue);
    expect(album.totalBytes, 4096);
    expect(library.pathFor(video.id, 'pl.4'), isNotNull);
  });

  test('reloads the index and keeps relative file names valid', () async {
    await addTrack('pl.4', 'Polski');
    final reopened = OfflineLibrary(
      rootDirectory: Directory('${root.path}/library'),
    );
    await reopened.init();
    final album = reopened.albumFor(video.id)!;
    expect(album.track('pl.4')!.label, 'Polski');
    expect(reopened.pathFor(video.id, 'pl.4'), isNotNull);
  });

  test('drops tracks whose files disappeared', () async {
    await addTrack('pl.4', 'Polski');
    await addTrack('en.4', 'English');
    await File(library.pathFor(video.id, 'pl.4')!).delete();

    final reopened = OfflineLibrary(
      rootDirectory: Directory('${root.path}/library'),
    );
    await reopened.init();
    expect(reopened.albumFor(video.id)!.hasTrack('pl.4'), isFalse);
    expect(reopened.albumFor(video.id)!.hasTrack('en.4'), isTrue);
  });

  test(
    'removing the last track removes the empty album and directory',
    () async {
      await addTrack('pl.4', 'Polski');
      final dir = await library.albumDirectory(video.id);
      expect(await dir.exists(), isTrue);

      await library.removeTrack(video.id, 'pl.4');
      expect(library.albumFor(video.id), isNull);
      expect(await dir.exists(), isFalse);
    },
  );

  test('removing an album deletes every file', () async {
    await addTrack('pl.4', 'Polski');
    await addTrack('en.4', 'English');
    final dir = await library.albumDirectory(video.id);

    await library.removeAlbum(video.id);
    expect(library.albums, isEmpty);
    expect(await dir.exists(), isFalse);
  });

  test('discarding an empty album keeps partial files for resume', () async {
    await library.ensureAlbum(video);
    final dir = await library.albumDirectory(video.id);
    final part = File('${dir.path}/pl.4.m4a.part');
    await part.writeAsBytes(List<int>.filled(128, 9));

    await library.discardEmptyAlbum(video.id);
    expect(library.albumFor(video.id), isNull);
    expect(await part.exists(), isTrue);
  });

  test('a corrupt index starts an empty library instead of crashing', () async {
    final index = File('${root.path}/library/library.json');
    await index.parent.create(recursive: true);
    await index.writeAsString('{ not json');

    final reopened = OfflineLibrary(
      rootDirectory: Directory('${root.path}/library'),
    );
    await reopened.init();
    expect(reopened.albums, isEmpty);
  });
}

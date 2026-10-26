import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yubbly_app/app_state.dart';
import 'package:yubbly_app/models.dart';
import 'package:yubbly_app/offline_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const video = VideoItem(
    id: 'zA-UHB2WcT4',
    title: 'Dwa języki. Jedna rozmowa.',
    channelName: 'Stand to Reason',
    durationMs: 600000,
  );
  late Directory root;
  late OfflineLibrary library;
  late List<MethodCall> calls;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('yubbly_offline_playback');
    library = OfflineLibrary(rootDirectory: Directory('${root.path}/library'));
    await library.init();
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('app.yubbly/player'), (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'history') return [];
          if (call.method == 'state') return <String, dynamic>{};
          return null;
        });
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> add(String id, String label) async {
    final dir = await library.albumDirectory(video.id);
    final file = File('${dir.path}/$id.m4a');
    await file.writeAsBytes(List<int>.filled(256, 3));
    await library.saveTrack(
      video,
      OfflineTrack(
        trackId: id,
        label: label,
        fileName: '$id.m4a',
        bytes: 256,
        bitrate: 128000,
        container: 'mp4',
        downloadedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  test('plays the local pair without resolving network streams', () async {
    await add('pl.4', 'Polski');
    await add('en.4', 'English (original)');
    final state = AppState(offline: library);
    addTearDown(state.dispose);

    await state.openAlbum(library.albumFor(video.id)!);
    expect(state.hasLocalPair, isTrue);

    await state.togglePlayback();
    final load = calls.firstWhere((c) => c.method == 'load');
    final args = Map<String, dynamic>.from(load.arguments as Map);
    expect(args['urlA'], startsWith('file://'));
    expect(args['urlB'], startsWith('file://'));
    expect(args['videoUrl'], isNull);
    expect((args['session'] as Map)['offline'], isTrue);
  });
}

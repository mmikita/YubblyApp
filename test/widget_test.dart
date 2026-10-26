import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yubbly_app/app_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yubbly_app/main.dart';
import 'package:yubbly_app/models.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('app.yubbly/player'),
      (call) async {
        if (call.method == 'state') return <String, dynamic>{};
        if (call.method == 'history') return [];
        return null;
      },
    );
  });
  setUpAll(() async {
    final loader = FontLoader('Roboto');
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          File('test/fonts/Roboto-Regular.ttf').readAsBytesSync(),
        ),
      ),
    );
    await loader.load();
    // Test-only subset: app Icons plus Flutter's default arrow_drop_down.
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      Future.value(
        ByteData.sublistView(
          File('test/fonts/MaterialIcons-Regular.otf').readAsBytesSync(),
        ),
      ),
    );
    await icons.load();
  });
  testWidgets('initial screen opens catalog and input dialog', (tester) async {
    final state = AppState();
    await tester.runAsync(state.init);
    await tester.pumpWidget(YubblyApp(initialState: state));
    await tester.pumpAndSettle();
    expect(find.text('Słuchaj w dwóch\njęzykach naraz.'), findsOneWidget);
    await tester.tap(find.text('Wybierz z katalogu'));
    await tester.pumpAndSettle();
    expect(find.text('Znajdź swój następny głos.'), findsOneWidget);
    await tester.tap(find.byTooltip('Dodaj film lub kanał'));
    await tester.pumpAndSettle();
    expect(find.text('Otwórz'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('narrow player layout and routing controls are usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('app.yubbly/player'),
      (call) async {
        calls.add(call);
        switch (call.method) {
          case 'state':
            return {
              'session': {
                'video': {
                  'id': 'zA-UHB2WcT4',
                  'title': 'Dwa języki. Jedna rozmowa.',
                  'channelName': 'Stand to Reason',
                  'channelUrl': 'https://www.youtube.com/@STRvideos',
                  'durationMs': 600000,
                },
                'trackA': 'pl.4',
                'trackB': 'en.4',
                'labelA': 'Polski',
                'labelB': 'English (original)',
                'mix': const MixSettings().toJson(),
                'withVideo': false,
              },
              'loaded': true,
              'playing': false,
              'positionMs': 95000,
              'durationMs': 600000,
            };
          case 'history':
            return [];
          default:
            return null;
        }
      },
    );
    final state = AppState();
    await tester.runAsync(state.init);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('preview'),
        child: YubblyApp(initialState: state),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Dwa języki. Jedna rozmowa.'), findsOneWidget);
    expect(find.text('01:35'), findsOneWidget);
    await expectLater(
      find.byKey(const Key('preview')),
      matchesGoldenFile('goldens/player.png'),
    );
    await tester.scrollUntilVisible(
      find.text('A lewo · B prawo'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -250));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('A lewo · B prawo'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      calls.any(
        (c) =>
            c.method == 'configure' && (c.arguments as Map)['mode'] == 'split',
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('app.yubbly/player'),
      null,
    );
  });
  testWidgets('stream failure offers a refresh action', (tester) async {
    final state = AppState();
    await tester.runAsync(state.init);
    state
      ..current = const VideoItem(
        id: 'zA-UHB2WcT4',
        title: 'Dwa języki. Jedna rozmowa.',
      )
      ..tracks = const [
        AudioChoice('pl.4', 'Polski', false),
        AudioChoice('en.4', 'English (original)', true),
      ]
      ..trackA = 'pl.4'
      ..trackB = 'en.4'
      ..error =
          'Nie udało się odtworzyć strumienia (HTTP 403 – YouTube odrzucił '
          'lub ograniczył strumień).';
    await tester.pumpWidget(YubblyApp(initialState: state));
    await tester.pump();
    expect(find.text('Odśwież'), findsOneWidget);
    expect(find.textContaining('HTTP 403'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

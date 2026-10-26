import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yubbly_app/js_challenge_solver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformJsChallengeSolver.channel, null);
  });

  void answer(void Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformJsChallengeSolver.channel, (
          call,
        ) async {
          calls.add(call);
          handler(call);
          return jsonEncode({'value': 'solved'});
        });
  }

  test('sends the player script once per player URL', () async {
    answer((_) {});
    final solver = PlatformJsChallengeSolver();

    expect(
      await solver.solveN(
        playerUrl: 'https://www.youtube.com/s/player/v1/base.js',
        playerJs: 'player-script',
        challenge: 'abc',
      ),
      'solved',
    );
    expect(
      await solver.solveN(
        playerUrl: 'https://www.youtube.com/s/player/v1/base.js',
        playerJs: 'player-script',
        challenge: 'def',
      ),
      'solved',
    );

    expect(calls, hasLength(2));
    expect((calls.first.arguments as Map)['playerJs'], 'player-script');
    expect((calls.last.arguments as Map)['playerJs'], isEmpty);
  });

  test(
    'retries with the full script when a native cache is unavailable',
    () async {
      answer((call) {
        final args = call.arguments as Map;
        if ((args['playerJs'] as String).isEmpty) {
          throw PlatformException(code: 'SOLVER', message: 'missing cache');
        }
      });
      final solver = PlatformJsChallengeSolver();
      const url = 'https://www.youtube.com/s/player/v2/base.js';

      expect(
        await solver.solveN(
          playerUrl: url,
          playerJs: 'player-script',
          challenge: 'abc',
        ),
        'solved',
      );
      expect(
        await solver.solveN(
          playerUrl: url,
          playerJs: 'player-script',
          challenge: 'def',
        ),
        'solved',
      );

      expect(calls, hasLength(3));
      expect((calls[1].arguments as Map)['playerJs'], isEmpty);
      expect((calls[2].arguments as Map)['playerJs'], 'player-script');
    },
  );
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yubbly_app/models.dart';

void main() {
  group('YouTube input validation', () {
    test('accepts watch, share, shorts, live and raw ids', () {
      for (final url in [
        'hAMa1nWM49A',
        'https://youtu.be/hAMa1nWM49A?t=30',
        'https://www.youtube.com/watch?v=hAMa1nWM49A&list=abc',
        'https://m.youtube.com/shorts/hAMa1nWM49A',
        'https://youtube.com/live/hAMa1nWM49A',
      ]) {
        expect(videoIdFromInput(url), 'hAMa1nWM49A');
      }
    });
    test('rejects lookalike hosts, arbitrary URLs and invalid ids', () {
      for (final url in [
        'https://youtube.com.evil.com/watch?v=hAMa1nWM49A',
        'https://evil.com/watch?v=hAMa1nWM49A',
        'file:///hAMa1nWM49A',
        'https://youtube.com/watch?v=abc',
        'javascript:alert(1)',
      ]) {
        expect(videoIdFromInput(url), isNull);
      }
    });
  });
  group('Share recipe', () {
    const recipe = ListeningRecipe(
      videoId: 'hAMa1nWM49A',
      trackA: 'pl.4',
      trackB: 'en.4',
      positionMs: 123456,
      settings: MixSettings(
        mode: MixMode.split,
        speed: 2.5,
        offsetMs: -350,
        swapped: true,
        contrast: 3,
        phase: 270,
      ),
    );
    test('round trip preserves all parameters including language variants', () {
      final decoded = ListeningRecipe.decode(recipe.encode());
      expect(decoded.videoId, recipe.videoId);
      expect(decoded.trackA, 'pl.4');
      expect(decoded.trackB, 'en.4');
      expect(decoded.positionMs, 123456);
      expect(decoded.settings.toJson(), recipe.settings.toJson());
      expect(recipe.encode().length, lessThan(1600));
    });
    test('rejects unsupported schema and oversized or malformed input', () {
      for (final s in [
        'yubbly://listen?v=2&d=abc',
        'https://youtube.com',
        'yubbly://listen?v=1&d=@!',
        'x' * 8001,
      ]) {
        expect(
          () => ListeningRecipe.decode(s),
          throwsA(isA<FormatException>()),
        );
      }
    });
    test('rejects identical tracks and unsafe positions', () {
      for (final position in [-1, 604800001, '30']) {
        final data = base64Url.encode(
          utf8.encode(
            jsonEncode({
              'video': 'hAMa1nWM49A',
              'a': 'pl',
              'b': 'en',
              'position': position,
              'mix': {},
            }),
          ),
        );
        expect(
          () => ListeningRecipe.decode('yubbly://listen?v=1&d=$data'),
          throwsFormatException,
        );
      }
      expect(
        () => ListeningRecipe.decode(
          const ListeningRecipe(
            videoId: 'hAMa1nWM49A',
            trackA: 'en',
            trackB: 'en',
            settings: MixSettings(),
          ).encode(),
        ),
        throwsFormatException,
      );
    });
    test('settings clamp external input to supported ranges', () {
      final s = MixSettings.fromJson({
        'period': 0,
        'speed': 50,
        'volume': -1,
        'depth': double.nan,
        'offsetMs': 90000,
        'curve': 'other',
        'mode': 'other',
      });
      expect(s.period, 2);
      expect(s.speed, 5);
      expect(s.volume, 0);
      expect(s.depth, .04);
      expect(s.offsetMs, 3000);
      expect(s.mode, MixMode.orbit);
      expect(s.curve, 'equal-power');
    });
  });
  test('time display handles hours', () {
    expect(clockText(3661000), '1:01:01');
    expect(clockText(-5), '00:00');
  });
}

import 'dart:convert';

import 'package:flutter/services.dart';

import 'web_embedded.dart';

/// Runs the bundled yt-dlp/ejs solver inside a hidden platform WebView.
class PlatformJsChallengeSolver implements NChallengeSolver {
  static const channel = MethodChannel('app.yubbly/js');

  String? _solverScript;
  String? _playerUrl;

  @override
  Future<String?> solveN({
    required String playerUrl,
    required String playerJs,
    required String challenge,
  }) async {
    _solverScript ??= await rootBundle.loadString('assets/js/solver.js');
    final samePlayer = _playerUrl == playerUrl;
    Future<String?> invoke({required bool withPlayerJs}) =>
        channel.invokeMethod<String>('solve', {
          'solver': _solverScript,
          // Native bridges cache the player script by URL. Re-sending ~2.5 MB
          // for every challenge is wasteful; an older bridge may not cache, so
          // a failure below retries once with the full script.
          'playerUrl': playerUrl,
          'playerJs': withPlayerJs ? playerJs : '',
          'challenge': challenge,
        });
    String? raw;
    try {
      raw = await invoke(withPlayerJs: !samePlayer);
    } on PlatformException {
      if (!samePlayer) rethrow;
      raw = await invoke(withPlayerJs: true);
    }
    if ((raw == null || raw.isEmpty) && samePlayer) {
      raw = await invoke(withPlayerJs: true);
    }
    _playerUrl = playerUrl;
    if (raw == null || raw.isEmpty) {
      throw StateError('Solver JavaScript nie zwrócił wyniku.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('Nieoczekiwany wynik solvera JavaScript.');
    }
    final error = decoded['error'];
    if (error is String && error.isNotEmpty) {
      throw StateError(
        'Nie udało się rozwiązać zabezpieczenia YouTube: $error',
      );
    }
    final value = decoded['value'];
    if (value is! String || value.isEmpty) {
      throw StateError('Solver JavaScript nie zwrócił wartości.');
    }
    return value;
  }
}

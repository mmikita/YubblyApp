import 'dart:convert';
import 'dart:io';

import 'package:yubbly_app/web_embedded.dart';

/// Node build of the same ejs solver used by the app's hidden WebView.
class NodeChallengeSolver implements NChallengeSolver {
  @override
  Future<String?> solveN({
    required String playerUrl,
    required String playerJs,
    required String challenge,
  }) async {
    final process = await Process.start('node', [
      'tool/node_solver.js',
      challenge,
    ]);
    process.stdin.write(playerJs);
    await process.stdin.close();
    final output = await process.stdout.transform(utf8.decoder).join();
    final errors = await process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode;
    if (code != 0) {
      throw StateError('node_solver.js failed ($code): $errors');
    }
    final value = output.trim();
    return value.isEmpty ? null : value;
  }
}

import 'dart:convert';

enum MixMode { split, orbit, mono, together }

/// User-facing names and explanations aligned with the Youbbly Wiki.
///
/// The serialized enum names stay unchanged for saved mixes and QR codes;
/// only the presentation uses the Wiki vocabulary.
extension MixModeInfo on MixMode {
  String get wikiName => switch (this) {
    MixMode.split => 'split-ear',
    MixMode.orbit => 'dual-combo',
    MixMode.mono => 'mono-combo',
    MixMode.together => 'stały miks',
  };

  String get chipLabel => switch (this) {
    MixMode.split => 'Split-ear · A L / B R',
    MixMode.orbit => 'Dual-combo · L↔R',
    MixMode.mono => 'Mono-combo · centrum',
    MixMode.together => 'Stały miks · oba',
  };

  String get summary => switch (this) {
    MixMode.orbit =>
      'Dual-combo: oba języki słychać w obu uszach. Gdy jeden przesuwa się '
          'w lewo, drugi przesuwa się w prawo, a po pół cyklu role się odwracają.',
    MixMode.split =>
      'Split-ear: język A stale w lewym uchu, język B stale w prawym. '
          'Bez sinusoidalnej zamiany.',
    MixMode.mono =>
      'Mono-combo: oba języki w centrum, z naprzemienną głośnością A i B.',
    MixMode.together =>
      'Stały miks: oba języki jednocześnie w obu uszach, bez falowania.',
  };
}

class MixSettings {
  final MixMode mode;
  final String curve;
  final double period, contrast, phase, microHz, depth, speed, volume;
  final int offsetMs;
  final bool swapped;
  const MixSettings({
    this.mode = MixMode.orbit,
    this.curve = 'equal-power',
    this.period = 60,
    this.contrast = 1,
    this.phase = 0,
    this.microHz = .3,
    this.depth = .04,
    this.speed = 1,
    this.volume = .7,
    this.offsetMs = 0,
    this.swapped = false,
  });

  factory MixSettings.fromJson(Map<String, dynamic> j) {
    double number(String k, double d, double min, double max) {
      final n = j[k];
      if (n is! num || !n.isFinite) {
        return d;
      }
      return n.toDouble().clamp(min, max);
    }

    return MixSettings(
      mode: MixMode.values.firstWhere(
        (m) => m.name == j['mode'],
        orElse: () => MixMode.orbit,
      ),
      curve: j['curve'] == 'linear' ? 'linear' : 'equal-power',
      period: number('period', 60, 2, 300),
      contrast: number('contrast', 1, 1, 5),
      phase: number('phase', 0, 0, 360),
      microHz: number('microHz', .3, 0, 2),
      depth: number('depth', .04, 0, .5),
      speed: number('speed', 1, 1, 5),
      volume: number('volume', .7, 0, 1),
      offsetMs: number('offsetMs', 0, -3000, 3000).round(),
      swapped: j['swapped'] == true,
    );
  }
  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'curve': curve,
    'period': period,
    'contrast': contrast,
    'phase': phase,
    'microHz': microHz,
    'depth': depth,
    'speed': speed,
    'volume': volume,
    'offsetMs': offsetMs,
    'swapped': swapped,
  };
  MixSettings withValues(Map<String, dynamic> updates) =>
      MixSettings.fromJson({...toJson(), ...updates});
}

class VideoItem {
  final String id, title, channelName, channelUrl;
  final int durationMs;
  const VideoItem({
    required this.id,
    required this.title,
    this.channelName = '',
    this.channelUrl = '',
    this.durationMs = 0,
  });
  String get url => 'https://www.youtube.com/watch?v=$id';
  String get thumbnail => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'channelName': channelName,
    'channelUrl': channelUrl,
    'durationMs': durationMs,
  };
  factory VideoItem.fromJson(Map<String, dynamic> j) => VideoItem(
    id: j['id'] as String,
    title: j['title'] as String? ?? 'Film z YouTube',
    channelName: j['channelName'] as String? ?? '',
    channelUrl: j['channelUrl'] as String? ?? '',
    durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
  );
}

class ChannelItem {
  final String name, url;
  const ChannelItem(this.name, this.url);
  Map<String, String> toJson() => {'name': name, 'url': url};
  factory ChannelItem.fromJson(Map<String, dynamic> j) =>
      ChannelItem(j['name'] as String, j['url'] as String);
}

class AudioChoice {
  final String id, name;
  final bool isDefault;
  const AudioChoice(this.id, this.name, this.isDefault);
  // YouTube's default flag is NOT proof that this is the original language.
  String get label => '$name${isDefault ? ' · domyślna' : ''}';
}

class ListeningRecipe {
  final String videoId, trackA, trackB;
  final int positionMs;
  final MixSettings settings;
  const ListeningRecipe({
    required this.videoId,
    required this.trackA,
    required this.trackB,
    required this.settings,
    this.positionMs = 0,
  });
  String encode() => Uri(
    scheme: 'yubbly',
    host: 'listen',
    queryParameters: {
      'v': '1',
      'd': base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'video': videoId,
                'a': trackA,
                'b': trackB,
                'position': positionMs,
                'mix': settings.toJson(),
              }),
            ),
          )
          .replaceAll('=', ''),
    },
  ).toString();
  static ListeningRecipe decode(String text) {
    if (text.length > 8000) {
      throw const FormatException('Kod QR jest za długi.');
    }
    final u = Uri.tryParse(text.trim());
    if (u == null ||
        u.scheme != 'yubbly' ||
        u.host != 'listen' ||
        u.queryParameters['v'] != '1') {
      throw const FormatException('To nie jest obsługiwany kod YubblyApp.');
    }
    final data = u.queryParameters['d'];
    if (data == null) throw const FormatException('Brak ustawień w kodzie.');
    final j = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(data))),
    );
    if (j is! Map<String, dynamic> ||
        !validVideoId(j['video']) ||
        j['a'] is! String ||
        j['b'] is! String ||
        j['a'] == j['b'] ||
        (j['a'] as String).length > 100 ||
        (j['b'] as String).length > 100 ||
        j['mix'] is! Map<String, dynamic>) {
      throw const FormatException('Nieprawidłowe ustawienia QR.');
    }
    final p = j['position'];
    if (p is! int || p < 0 || p > 604800000) {
      throw const FormatException('Nieprawidłowa pozycja.');
    }
    return ListeningRecipe(
      videoId: j['video'],
      trackA: j['a'],
      trackB: j['b'],
      positionMs: p,
      settings: MixSettings.fromJson(j['mix']),
    );
  }
}

bool validVideoId(Object? v) =>
    v is String && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(v);

String? videoIdFromInput(String input) {
  final text = input.trim();
  if (validVideoId(text)) return text;
  final u = Uri.tryParse(text);
  if (u == null || !['http', 'https'].contains(u.scheme)) return null;
  final host = u.host.toLowerCase();
  String? id;
  if (host == 'youtu.be') {
    id = u.pathSegments.firstOrNull;
  } else if ([
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
  ].contains(host)) {
    id = u.queryParameters['v'];
    if (id == null &&
        u.pathSegments.length >= 2 &&
        ['shorts', 'live', 'embed'].contains(u.pathSegments.first)) {
      id = u.pathSegments[1];
    }
  }
  return validVideoId(id) ? id : null;
}

String clockText(int ms) {
  final sec = (ms / 1000).floor().clamp(0, 604800);
  final h = sec ~/ 3600, m = (sec ~/ 60) % 60, s = sec % 60;
  return '${h > 0 ? '$h:' : ''}${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

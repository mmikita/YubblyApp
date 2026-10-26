import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'youtube_repository.dart';

class AppState extends ChangeNotifier {
  static const native = MethodChannel('app.yubbly/player');
  final YoutubeRepository youtube;
  AppState({YoutubeRepository? youtube})
    : youtube = youtube ?? YoutubeRepository();

  /// Android, iOS and macOS all expose the `app.yubbly/player` channel.
  static bool get nativePlaybackSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Only Android embeds a video platform view. Apple targets play audio.
  static bool get videoSurfaceSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// AVFoundation cannot decode YouTube's WebM/Opus streams.
  static bool get requiresMp4Audio =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get hasVideoSurface => videoSurfaceSupported;
  SharedPreferences? _prefs;
  Timer? _poll;
  bool _polling = false,
      busy = false,
      playing = false,
      buffering = false,
      withVideo = false;
  String? error, trackA, trackB;
  String _loadedPair = '';
  VideoItem? current;
  List<AudioChoice> tracks = [];
  MixSettings mix = const MixSettings();
  int positionMs = 0, durationMs = 0, driftMs = 0;
  List<VideoItem> videos = [];
  List<ChannelItem> channels = [];
  List<Map<String, dynamic>> history = [];
  final Set<String> favorites = {};
  final Map<String, int> verifiedTracks = {};
  bool get canPlay =>
      current != null && trackA != null && trackB != null && trackA != trackB;
  String get pair => '${current?.id}|$trackA|$trackB|$withVideo';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final seed =
        jsonDecode(await rootBundle.loadString('assets/catalog.json'))
            as Map<String, dynamic>;
    Map<String, dynamic> data = seed;
    try {
      final saved = _prefs!.getString('catalog.v1');
      if (saved != null) data = jsonDecode(saved) as Map<String, dynamic>;
    } catch (_) {
      error = 'Nie udało się odczytać katalogu. Przywrócono listę startową.';
    }
    videos = (data['videos'] as List)
        .map((e) => VideoItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    channels = (data['channels'] as List)
        .map((e) => ChannelItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    favorites.addAll(_prefs!.getStringList('favorites') ?? []);
    try {
      mix = MixSettings.fromJson(jsonDecode(_prefs!.getString('mix') ?? '{}'));
    } catch (_) {
      mix = const MixSettings();
    }
    native.setMethodCallHandler((call) async {
      if (call.method == 'incoming' && call.arguments is String) {
        await openInput(call.arguments as String);
      }
    });
    if (nativePlaybackSupported) {
      try {
        final snapshot = await native.invokeMapMethod<String, dynamic>('state');
        if (snapshot != null) _applyState(snapshot, restore: true);
        await refreshHistory();
        final incoming = await native.invokeMethod<String>('initialLink');
        if (incoming != null && incoming.isNotEmpty) await openInput(incoming);
      } on PlatformException catch (e) {
        error = e.message;
      }
      _poll = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _readState(),
      );
    }
    notifyListeners();
  }

  Future<void> _readState() async {
    if (_polling) return;
    _polling = true;
    try {
      final s = await native.invokeMapMethod<String, dynamic>('state');
      if (s != null) {
        _applyState(s);
        notifyListeners();
      }
    } catch (_) {
      /* An Activity recreation can temporarily detach the channel. */
    } finally {
      _polling = false;
    }
  }

  void _applyState(Map<String, dynamic> s, {bool restore = false}) {
    final session = s['session'];
    if (restore && session is Map && session['video'] is Map) {
      final j = Map<String, dynamic>.from(session);
      current = VideoItem.fromJson(Map<String, dynamic>.from(j['video']));
      trackA = j['trackA'] as String?;
      trackB = j['trackB'] as String?;
      withVideo = j['withVideo'] == true && hasVideoSurface;
      mix = MixSettings.fromJson(Map<String, dynamic>.from(j['mix'] ?? {}));
      tracks = [
        if (trackA != null)
          AudioChoice(trackA!, j['labelA'] as String? ?? trackA!, false),
        if (trackB != null)
          AudioChoice(trackB!, j['labelB'] as String? ?? trackB!, false),
      ];
      if (s['loaded'] == true) _loadedPair = pair;
    }
    if (session is Map &&
        session['video'] is Map &&
        session['video']['id'] == current?.id) {
      positionMs = (s['positionMs'] as num?)?.toInt() ?? positionMs;
      durationMs =
          (s['durationMs'] as num?)?.toInt() ?? current?.durationMs ?? 0;
      if (durationMs <= 0) durationMs = current?.durationMs ?? 0;
      playing = s['playing'] == true;
      buffering = s['buffering'] == true;
      driftMs = (s['driftMs'] as num?)?.toInt() ?? 0;
      final e = s['error'];
      if (e is String && e.isNotEmpty) {
        error = e;
        _loadedPair = '';
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      error = friendlyError(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static String friendlyError(Object e) {
    if (e is FormatException) return e.message;
    if (e is StateError) return e.message;
    if (e is TimeoutException) {
      return 'YouTube nie odpowiedział na czas. Spróbuj ponownie.';
    }
    if (e is PlatformException) {
      return e.message ?? 'Nie udało się uruchomić odtwarzacza.';
    }
    return 'Nie udało się pobrać materiału z YouTube. Sprawdź połączenie i spróbuj ponownie. '
        'Film może być niedostępny lub YouTube wymaga aktualizacji ekstraktora.';
  }

  Future<void> openInput(String raw) async {
    final link =
        RegExp(r'(?:https?://|yubbly://)[^\s]+').firstMatch(raw)?.group(0) ??
        raw.trim();
    await run(() async {
      if (link.startsWith('yubbly:')) {
        final recipe = ListeningRecipe.decode(link);
        await _inspect(recipe.videoId);
        mix = recipe.settings;
        positionMs = recipe.positionMs;
        trackA = tracks.any((t) => t.id == recipe.trackA)
            ? recipe.trackA
            : null;
        trackB = tracks.any((t) => t.id == recipe.trackB)
            ? recipe.trackB
            : null;
        if (trackA == null || trackB == null) {
          error =
              'Języki z kodu QR nie są obecnie dostępne. Wybierz je ponownie.';
        }
        await _saveMix();
      } else {
        final id = videoIdFromInput(link);
        if (id != null) {
          await _inspect(id);
        } else {
          final c = await youtube.channel(link);
          if (!channels.any((e) => e.url == c.url)) channels.insert(0, c);
          await _saveCatalog();
        }
      }
    });
  }

  Future<void> inspect(VideoItem v) => run(() => _inspect(v.id));

  Future<void> _inspect(String id) async {
    final result = await youtube.inspect(id, mp4Only: requiresMp4Audio);
    await native.invokeMethod('stop');
    _loadedPair = '';
    playing = false;
    buffering = false;
    current = result.video;
    tracks = result.tracks;
    verifiedTracks[id] = tracks.length;
    await refreshHistory();
    final previous = history.where((h) => h['id'] == id).firstOrNull;
    positionMs = previous?['complete'] == true
        ? 0
        : (previous?['positionMs'] as num?)?.toInt() ?? 0;
    durationMs = current!.durationMs;
    trackA =
        tracks.where((t) => t.id.startsWith('pl')).firstOrNull?.id ??
        tracks.firstOrNull?.id;
    trackB =
        tracks
            .where((t) => t.id != trackA && t.id.startsWith('en'))
            .firstOrNull
            ?.id ??
        tracks.where((t) => t.id != trackA).firstOrNull?.id;
    videos.removeWhere((v) => v.id == id);
    videos.insert(0, current!);
    if (!channels.any((c) => c.url == current!.channelUrl) &&
        current!.channelUrl.isNotEmpty) {
      channels.insert(
        0,
        ChannelItem(current!.channelName, current!.channelUrl),
      );
    }
    await _saveCatalog();
    if (tracks.length < 2) {
      error = requiresMp4Audio
          ? 'Ten film udostępnia mniej niż dwie ścieżki audio w formacie MP4. '
                'AVFoundation na iOS/macOS nie odtwarza WebM/Opus. Wybierz inny film.'
          : 'Ten film udostępnia mniej niż dwie ścieżki audio. Wybierz inny film. Napisy nie są dubbingiem.';
    }
  }

  void selectTracks({String? a, String? b}) {
    if (a != null) trackA = a;
    if (b != null) trackB = b;
    notifyListeners();
  }

  Future<void> togglePlayback({bool refreshStreams = false}) async {
    if (busy) return;
    if ((playing || buffering) && !refreshStreams) {
      await native.invokeMethod('pause');
      playing = false;
      buffering = false;
      notifyListeners();
      return;
    }
    if (!canPlay) return;
    if (refreshStreams) _loadedPair = '';
    await run(() async {
      if (refreshStreams) await native.invokeMethod('stop');
      if (!refreshStreams && _loadedPair == pair) {
        await native.invokeMethod('play');
        return;
      }
      final urls = await youtube.streams(
        current!.id,
        trackA!,
        trackB!,
        video: withVideo && hasVideoSurface,
        mp4Only: requiresMp4Audio,
      );
      final session = {
        'video': current!.toJson(),
        'trackA': trackA,
        'trackB': trackB,
        'labelA': tracks.firstWhere((t) => t.id == trackA).name,
        'labelB': tracks.firstWhere((t) => t.id == trackB).name,
        'mix': mix.toJson(),
        'withVideo': withVideo,
      };
      await native.invokeMethod('load', {
        ...urls,
        'session': session,
        'positionMs': positionMs,
      });
      _loadedPair = pair;
    });
  }

  Future<void> seek(int ms) async {
    positionMs = ms.clamp(0, durationMs > 0 ? durationMs : 604800000);
    if (_loadedPair == pair) {
      await native.invokeMethod('seek', {'positionMs': positionMs});
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await native.invokeMethod('stop');
    _loadedPair = '';
    playing = false;
    buffering = false;
    await youtube.releaseStreams();
    await refreshHistory();
    notifyListeners();
  }

  Future<void> changeMix(Map<String, dynamic> values) async {
    mix = mix.withValues(values);
    notifyListeners();
    await native.invokeMethod('configure', mix.toJson());
    await _saveMix();
  }

  void setVideo(bool value) {
    if (value && !hasVideoSurface) return;
    withVideo = value;
    notifyListeners();
  }

  Future<void> _saveMix() async =>
      _prefs?.setString('mix', jsonEncode(mix.toJson()));
  Future<void> _saveCatalog() async => _prefs?.setString(
    'catalog.v1',
    jsonEncode({
      'videos': videos.map((v) => v.toJson()).toList(),
      'channels': channels.map((c) => c.toJson()).toList(),
    }),
  );
  Future<void> toggleFavorite(String id) async {
    if (!favorites.add(id)) favorites.remove(id);
    await _prefs?.setStringList('favorites', favorites.toList());
    notifyListeners();
  }

  Future<void> removeVideo(String id) async {
    videos.removeWhere((v) => v.id == id);
    await _saveCatalog();
    notifyListeners();
  }

  Future<void> removeChannel(ChannelItem c) async {
    channels.removeWhere((e) => e.url == c.url);
    await _saveCatalog();
    notifyListeners();
  }

  Future<void> refreshHistory() async {
    final list = await native.invokeListMethod<dynamic>('history') ?? [];
    history = list.map((e) => Map<String, dynamic>.from(e)).toList()
      ..sort(
        (a, b) =>
            (b['lastPlayedMs'] as num).compareTo(a['lastPlayedMs'] as num),
      );
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await native.invokeMethod('clearHistory');
    history = [];
    notifyListeners();
  }

  ListeningRecipe recipe() => ListeningRecipe(
    videoId: current!.id,
    trackA: trackA!,
    trackB: trackB!,
    settings: mix,
    positionMs: positionMs,
  );
  @override
  void dispose() {
    _poll?.cancel();
    youtube.close();
    native.setMethodCallHandler(null);
    super.dispose();
  }
}

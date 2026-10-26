import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    show ChannelUploadsList;
import 'app_state.dart';
import 'models.dart';
import 'offline_library.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YubblyApp());
}

const mint = Color(0xff8be8c2),
    amber = Color(0xffffc078),
    panel = Color(0xff18232d);

String offlineSizeText(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).round()} kB';
  return '$bytes B';
}

class YubblyApp extends StatelessWidget {
  final AppState? initialState;
  const YubblyApp({super.key, this.initialState});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'YubblyApp',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff0d151c),
      colorScheme: ColorScheme.fromSeed(
        seedColor: mint,
        brightness: Brightness.dark,
        primary: mint,
        secondary: amber,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xff0d151c),
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: Home(initialState: initialState),
  );
}

class Home extends StatefulWidget {
  final AppState? initialState;
  const Home({super.key, this.initialState});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final AppState state;
  int tab = 0;
  bool initialized = false;
  String query = '';
  bool onlyFavorites = false;
  @override
  void initState() {
    super.initState();
    state = widget.initialState ?? AppState();
    state.addListener(changed);
    if (widget.initialState == null) {
      initialize();
    } else {
      initialized = true;
    }
  }

  Future<void> initialize() async {
    try {
      await state.init();
    } catch (e) {
      state.error = AppState.friendlyError(e);
    }
    if (mounted) setState(() => initialized = true);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    state.removeListener(changed);
    state.dispose();
    super.dispose();
  }

  Future<void> input() async {
    final c = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dodaj film lub kanał'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.url,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Link YouTube lub kod yubbly://…',
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Otwórz'),
          ),
        ],
      ),
    );
    // The dialog transition may still reference its controller; disposal follows a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    if (value != null && value.trim().isNotEmpty) {
      await state.openInput(value);
      if (mounted) setState(() => tab = state.current != null ? 0 : 1);
    }
  }

  Future<void> scan() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (value != null) {
      await state.openInput(value);
      if (mounted) setState(() => tab = 0);
    }
  }

  void showError(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppState.friendlyError(e))));
    }
  }

  Future<void> act(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      showError(e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: mint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.graphic_eq,
              color: Color(0xff0d151c),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YubblyApp',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
                  ),
                  Text(
                    'DWA JĘZYKI. JEDEN RYTM.',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.7,
                      color: mint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Skanuj QR',
          onPressed: state.busy ? null : scan,
          icon: const Icon(Icons.qr_code_scanner),
        ),
        IconButton(
          tooltip: 'Dodaj film lub kanał',
          onPressed: state.busy ? null : input,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    ),
    body: !initialized
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Column(
              children: [
                if (state.busy) const LinearProgressIndicator(minHeight: 2),
                if (state.error != null)
                  Container(
                    color: const Color(0xff442d2e),
                    padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            state.error!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (state.canPlay)
                          TextButton(
                            onPressed: state.busy
                                ? null
                                : () => act(
                                    () => state.togglePlayback(
                                      refreshStreams: true,
                                    ),
                                  ),
                            child: const Text('Odśwież'),
                          ),
                        IconButton(
                          tooltip: 'Zamknij komunikat',
                          onPressed: () => setState(() => state.error = null),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: tab == 0
                          ? player()
                          : tab == 1
                          ? catalog()
                          : tab == 2
                          ? library()
                          : history(),
                    ),
                  ),
                ),
                if (tab != 0 && state.current != null) miniPlayer(),
              ],
            ),
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) {
        setState(() => tab = v);
        if (v == 3) act(state.refreshHistory);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.tune), label: 'Odtwarzacz'),
        NavigationDestination(
          icon: Icon(Icons.video_library_outlined),
          label: 'Odkrywaj',
        ),
        NavigationDestination(
          icon: Icon(Icons.offline_pin_outlined),
          label: 'Biblioteka',
        ),
        NavigationDestination(icon: Icon(Icons.history), label: 'Historia'),
      ],
    ),
  );

  Widget player() {
    final v = state.current;
    if (v == null) {
      return ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const SizedBox(height: 28),
          const Icon(Icons.headphones, size: 70, color: mint),
          const SizedBox(height: 24),
          const Text(
            'Słuchaj w dwóch\njęzykach naraz.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Wybierz film z dubbingiem. Ustaw języki, załóż słuchawki i znajdź swój rytm.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, height: 1.5),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: input,
            icon: const Icon(Icons.link),
            label: const Text('Wklej link YouTube'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => setState(() => tab = 1),
            icon: const Icon(Icons.explore_outlined),
            label: const Text('Wybierz z katalogu'),
          ),
          const SizedBox(height: 26),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Działa bez konta i bez własnego serwera.\nDostępność dubbingu sprawdzamy po otwarciu filmu.',
                style: TextStyle(color: Colors.white70, height: 1.6),
              ),
            ),
          ),
        ],
      );
    }
    final album = state.albums.where((a) => a.video.id == v.id).firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.waves, color: mint, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      state.buffering
                          ? 'BUFOROWANIE'
                          : state.playing
                          ? 'TERAZ SŁUCHASZ'
                          : 'GOTOWY DO SŁUCHANIA',
                      style: const TextStyle(
                        color: mint,
                        fontSize: 10,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${state.mix.speed.toStringAsFixed(2)}×',
                      style: const TextStyle(
                        color: amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (state.withVideo &&
                    !kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.android)
                  const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: AndroidView(viewType: 'app.yubbly/video'),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 7,
                      child: Image.network(
                        v.thumbnail,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xff24333d),
                          child: Icon(Icons.headphones, size: 64, color: mint),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  v.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  v.channelName,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Slider(
                  value: state.positionMs.toDouble().clamp(
                    0,
                    state.durationMs > 0 ? state.durationMs.toDouble() : 1,
                  ),
                  max: state.durationMs > 0 ? state.durationMs.toDouble() : 1,
                  onChanged: state.durationMs > 0
                      ? (x) => act(() => state.seek(x.round()))
                      : null,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      clockText(state.positionMs),
                      style: const TextStyle(
                        fontFeatures: [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      clockText(state.durationMs),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Cofnij 10 sekund',
                      onPressed: () =>
                          act(() => state.seek(state.positionMs - 10000)),
                      icon: const Icon(Icons.replay_10),
                    ),
                    const SizedBox(width: 16),
                    Tooltip(
                      message: state.hasLocalPair
                          ? 'Odtwórz z plików offline'
                          : 'Odtwórz online',
                      child: SizedBox(
                        width: 74,
                        height: 58,
                        child: FilledButton(
                          onPressed: state.busy || !state.canPlay
                              ? null
                              : () => act(state.togglePlayback),
                          child: state.busy || state.buffering
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  state.playing
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  size: 32,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      tooltip: 'Dalej 10 sekund',
                      onPressed: () =>
                          act(() => state.seek(state.positionMs + 10000)),
                      icon: const Icon(Icons.forward_10),
                    ),
                    IconButton(
                      tooltip: 'Zatrzymaj także w tle',
                      onPressed: () => act(state.stop),
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      state.hasLocalPair
                          ? Icons.offline_pin
                          : Icons.cloud_queue,
                      size: 14,
                      color: state.hasLocalPair ? mint : Colors.white54,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        state.hasLocalPair
                            ? 'Odtwarzanie offline z plików na dysku'
                            : 'Odtwarzanie online — pobieranie nie jest wymagane',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () => act(() => state.toggleFavorite(v.id)),
                      icon: Icon(
                        state.favorites.contains(v.id)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 18,
                      ),
                      label: const Text('Zapisz'),
                    ),
                    TextButton.icon(
                      onPressed: state.canPlay
                          ? () => shareRecipe(context, state.recipe(), v.title)
                          : null,
                      icon: const Icon(Icons.qr_code_2, size: 20),
                      label: const Text('Udostępnij'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'TWOJE JĘZYKI',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.7,
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final a = trackPicker(
              'A · pierwszy język',
              state.trackA,
              (x) => state.selectTracks(a: x),
              mint,
            );
            final b = trackPicker(
              'B · drugi język',
              state.trackB,
              (x) => state.selectTracks(b: x),
              amber,
            );
            return c.maxWidth < 390
                ? Column(children: [a, const SizedBox(height: 10), b])
                : Row(
                    children: [
                      Expanded(child: a),
                      const SizedBox(width: 10),
                      Expanded(child: b),
                    ],
                  );
          },
        ),
        const SizedBox(height: 6),
        Text(
          'Oznaczenie „oryginał” pochodzi z nazwy ścieżki YouTube. „Domyślna” nie musi oznaczać oryginału.',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: .45),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      state.hasLocalPair
                          ? Icons.offline_pin
                          : Icons.cloud_download_outlined,
                      color: state.hasLocalPair ? mint : amber,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.hasLocalPair
                            ? 'Gotowe do słuchania offline'
                            : 'Słuchaj także bez internetu',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (state.downloading)
                      Text(
                        '${(state.downloadProgress * 100).round()}%',
                        style: const TextStyle(
                          color: amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  state.downloading
                      ? (state.downloadLabel ?? 'Pobieranie…')
                      : state.hasLocalPair
                      ? 'M4A/AAC ~128 kbps · ${offlineSizeText(album?.totalBytes ?? 0)} · '
                            'odtwarzanie bez sieci'
                      : 'Odtwarzanie online działa od razu. Pobierz oba języki '
                            '(M4A/AAC ~128 kbps), jeśli chcesz słuchać bez '
                            'internetu. Pobieranie nie przerywa odtwarzania.',
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: Colors.white60,
                  ),
                ),
                if (state.downloading) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: state.downloadProgress),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: state.cancelDownload,
                      child: const Text('Anuluj'),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (!state.hasLocalPair)
                        FilledButton.icon(
                          onPressed: state.busy || !state.canPlay
                              ? null
                              : () => act(state.downloadSelected),
                          icon: const Icon(Icons.download, size: 18),
                          label: Text(
                            state.offlinePath(state.trackA ?? '') != null ||
                                    state.offlinePath(state.trackB ?? '') !=
                                        null
                                ? 'Pobierz brakujące offline'
                                : 'Pobierz A+B offline',
                          ),
                        ),
                      if (album != null && !state.hasLocalPair)
                        OutlinedButton.icon(
                          onPressed: state.busy
                              ? null
                              : () => act(() => state.openAlbum(album)),
                          icon: const Icon(
                            Icons.library_music_outlined,
                            size: 18,
                          ),
                          label: const Text('Użyj pobranych plików'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'SPOSÓB SŁUCHANIA',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.7,
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            mode(MixMode.orbit, MixMode.orbit.chipLabel, Icons.sync),
            mode(MixMode.split, MixMode.split.chipLabel, Icons.headphones),
            mode(MixMode.mono, MixMode.mono.chipLabel, Icons.waves),
            mode(MixMode.together, MixMode.together.chipLabel, Icons.merge),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          state.mix.mode.summary,
          style: const TextStyle(
            fontSize: 11,
            height: 1.45,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                if (state.mix.mode == MixMode.orbit ||
                    state.mix.mode == MixMode.mono)
                  settingSlider(
                    'Pełny cykl · czas nagrania',
                    '${state.mix.period.round()} s',
                    state.mix.period,
                    2,
                    300,
                    (x) => state.changeMix({'period': x}),
                  ),
                settingSlider(
                  'Prędkość',
                  '${state.mix.speed.toStringAsFixed(2)}×',
                  state.mix.speed,
                  1,
                  5,
                  (x) => state.changeMix({'speed': (x * 4).round() / 4}),
                ),
                settingSlider(
                  'Głośność',
                  '${(state.mix.volume * 100).round()}%',
                  state.mix.volume,
                  0,
                  1,
                  (x) => state.changeMix({'volume': x}),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Zamień lewe i prawe ucho',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: state.mix.swapped,
                  onChanged: (x) => act(() => state.changeMix({'swapped': x})),
                ),
              ],
            ),
          ),
        ),
        ExpansionTile(
          title: const Text(
            'Ustawienia zaawansowane',
            style: TextStyle(fontSize: 14),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'equal-power',
                        label: Text('Equal power'),
                      ),
                      ButtonSegment(value: 'linear', label: Text('Liniowo')),
                    ],
                    selected: {state.mix.curve},
                    onSelectionChanged: (s) =>
                        act(() => state.changeMix({'curve': s.first})),
                  ),
                  const SizedBox(height: 12),
                  settingSlider(
                    'Kontrast',
                    state.mix.contrast.toStringAsFixed(1),
                    state.mix.contrast,
                    1,
                    5,
                    (x) => state.changeMix({'contrast': x}),
                  ),
                  settingSlider(
                    'Faza',
                    '${state.mix.phase.round()}°',
                    state.mix.phase,
                    0,
                    360,
                    (x) => state.changeMix({'phase': x}),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => state.changeMix({'phase': 0}),
                          child: const Text('Środek · 0°'),
                        ),
                        TextButton(
                          onPressed: () => state.changeMix({'phase': 270}),
                          child: const Text('A lewo / B prawo · 270°'),
                        ),
                        TextButton(
                          onPressed: () => state.changeMix({'phase': 90}),
                          child: const Text('Odwrotnie · 90°'),
                        ),
                      ],
                    ),
                  ),
                  settingSlider(
                    'Mikromodulacja',
                    '${(state.mix.depth * 100).round()}%',
                    state.mix.depth,
                    0,
                    .5,
                    (x) => state.changeMix({'depth': x}),
                  ),
                  settingSlider(
                    'Częstotliwość mikro',
                    '${state.mix.microHz.toStringAsFixed(2)} Hz',
                    state.mix.microHz,
                    0,
                    2,
                    (x) => state.changeMix({'microHz': x}),
                  ),
                  settingSlider(
                    'Przesunięcie B · + = późniejszy fragment',
                    '${state.mix.offsetMs} ms',
                    state.mix.offsetMs.toDouble(),
                    -3000,
                    3000,
                    (x) => state.changeMix({'offsetMs': (x / 50).round() * 50}),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Odtwarzaj również obraz'),
                    subtitle: Text(
                      state.hasVideoSurface
                          ? 'Zmiana wymaga pauzy i ponownego uruchomienia.'
                          : 'Obraz jest dostępny tylko na Androidzie. '
                                'Na macOS i iOS odtwarzane jest samo audio.',
                    ),
                    value: state.hasVideoSurface && state.withVideo,
                    onChanged:
                        !state.hasVideoSurface ||
                            state.playing ||
                            state.buffering
                        ? null
                        : (x) => state.setVideo(x),
                  ),
                  const Text(
                    'Dubbing może mieć inne tempo wypowiedzi niż oryginał. Korekta przesunięcia wyrównuje czas ścieżek, nie poszczególne słowa.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => act(
                      () => state.changeMix(const MixSettings().toJson()),
                    ),
                    child: const Text('Przywróć ustawienia domyślne'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Słuchawki dają pełny efekt stereo. Po zminimalizowaniu steruj odtwarzaniem z powiadomienia.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }

  Widget trackPicker(
    String label,
    String? value,
    void Function(String?) onChange,
    Color color,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    key: ValueKey('$label|$value|${state.current?.id}'),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: color, fontSize: 12),
    ),
    items: state.tracks
        .map(
          (t) => DropdownMenuItem(
            value: t.id,
            child: Text(
              t.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        )
        .toList(),
    onChanged: state.busy || state.playing || state.buffering ? null : onChange,
  );
  Widget mode(MixMode value, String label, IconData icon) => ChoiceChip(
    selected: state.mix.mode == value,
    avatar: Icon(icon, size: 17),
    label: Text(label, style: const TextStyle(fontSize: 12)),
    onSelected: (_) => act(() => state.changeMix({'mode': value.name})),
  );
  Widget settingSlider(
    String title,
    String label,
    double value,
    double min,
    double max,
    Future<void> Function(double) change,
  ) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12))),
          Text(
            label,
            style: const TextStyle(
              color: mint,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: (x) => act(() => change(x)),
      ),
    ],
  );
  Widget miniPlayer() => Material(
    color: panel,
    child: ListTile(
      onTap: () => setState(() => tab = 0),
      leading: const Icon(Icons.graphic_eq, color: mint),
      title: Text(
        state.current!.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${clockText(state.positionMs)} · ${state.mix.speed.toStringAsFixed(2)}×',
      ),
      trailing: IconButton(
        tooltip: state.playing ? 'Pauza' : 'Odtwórz',
        onPressed: state.busy || !state.canPlay
            ? null
            : () => act(state.togglePlayback),
        icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
      ),
    ),
  );

  Widget catalog() {
    final q = query.toLowerCase();
    final filtered = state.videos
        .where(
          (v) =>
              (!onlyFavorites || state.favorites.contains(v.id)) &&
              '${v.title} ${v.channelName}'.toLowerCase().contains(q),
        )
        .toList();
    final cc = state.channels
        .where((c) => c.name.toLowerCase().contains(q))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Znajdź swój następny głos.',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Katalog społeczności Youbbly · języki sprawdzane przy otwarciu filmu',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 18),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Szukaj w swoim katalogu…',
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: Text(
                'KANAŁY',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.5,
                  color: Colors.white54,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: state.busy ? null : input,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Dodaj'),
            ),
          ],
        ),
        SizedBox(
          height: 114,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cc.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = cc[i];
              return SizedBox(
                width: 148,
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChannelPage(
                          channel: c,
                          state: state,
                          onSelect: (v) async {
                            Navigator.pop(context);
                            await state.inspect(v);
                            if (mounted) setState(() => tab = 0);
                          },
                        ),
                      ),
                    ),
                    onLongPress: () => channelMenu(c),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.subscriptions_outlined,
                            color: amber,
                            size: 22,
                          ),
                          const Spacer(),
                          Text(
                            c.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'FILMY · ${filtered.length}',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.5,
                  color: Colors.white54,
                ),
              ),
            ),
            FilterChip(
              label: const Text('Ulubione'),
              selected: onlyFavorites,
              onSelected: (v) => setState(() => onlyFavorites = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Brak pasujących filmów. Dodaj link lub zmień filtr.'),
          ),
        for (final v in filtered) videoTile(v),
      ],
    );
  }

  Future<void> channelMenu(ChannelItem c) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Otwórz kanał w YouTube'),
              onTap: () {
                Navigator.pop(context);
                launchUrl(
                  Uri.parse(c.url),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Usuń z katalogu'),
              onTap: () {
                Navigator.pop(context);
                state.removeChannel(c);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget videoTile(VideoItem v, {String? subtitle}) => Card(
    margin: const EdgeInsets.symmetric(vertical: 5),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      onTap: state.busy
          ? null
          : () async {
              await state.inspect(v);
              if (mounted) setState(() => tab = 0);
            },
      leading: SizedBox(
        width: 86,
        height: 54,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            v.thumbnail,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.movie_outlined),
          ),
        ),
      ),
      title: Text(
        v.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle ??
            '${v.channelName}${state.verifiedTracks[v.id] != null ? ' · ${state.verifiedTracks[v.id]} audio' : ''}${state.history.any((h) => h['id'] == v.id) ? ' · słuchane' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, color: Colors.white54),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Opcje filmu',
        onSelected: (action) {
          if (action == 'favorite') state.toggleFavorite(v.id);
          if (action == 'remove') state.removeVideo(v.id);
          if (action == 'youtube') {
            launchUrl(Uri.parse(v.url), mode: LaunchMode.externalApplication);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'favorite',
            child: Text(
              state.favorites.contains(v.id)
                  ? 'Usuń z ulubionych'
                  : 'Dodaj do ulubionych',
            ),
          ),
          const PopupMenuItem(
            value: 'youtube',
            child: Text('Otwórz w YouTube'),
          ),
          const PopupMenuItem(value: 'remove', child: Text('Usuń z katalogu')),
        ],
      ),
    ),
  );
  Widget library() {
    final albums = state.albums;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Biblioteka offline',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Jeden film, podpisany zestaw języków. Pliki M4A/AAC ~128 kbps zostają w pamięci aplikacji.',
          style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.45),
        ),
        const SizedBox(height: 18),
        if (albums.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 70),
            child: Column(
              children: [
                Icon(Icons.offline_pin_outlined, size: 52, color: mint),
                SizedBox(height: 16),
                Text('Brak pobranych zestawów.'),
                SizedBox(height: 8),
                Text(
                  'Otwórz film, wybierz dwa języki i naciśnij „Pobierz A+B”.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
        for (final album in albums)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 92,
                          height: 62,
                          child: Image.network(
                            album.video.thumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: panel,
                              child: const Icon(
                                Icons.movie_outlined,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album.video.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              album.video.channelName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${album.trackList.length} ${album.trackList.length == 1 ? 'język' : 'języki'} · ${offlineSizeText(album.totalBytes)}',
                              style: const TextStyle(fontSize: 11, color: mint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final track in album.trackList)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(
                            Icons.record_voice_over_outlined,
                            size: 14,
                          ),
                          label: Text(
                            track.label,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      FilledButton.icon(
                        onPressed: state.busy
                            ? null
                            : () => act(() async {
                                await state.openAlbum(album, play: true);
                                if (mounted) setState(() => tab = 0);
                              }),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Odtwórz offline'),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.busy
                            ? null
                            : () => act(() async {
                                await state.openAlbum(album);
                                await state.inspect(album.video);
                                if (mounted) setState(() => tab = 0);
                              }),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Dodaj język'),
                      ),
                      IconButton(
                        tooltip: 'Usuń album z dysku',
                        onPressed: state.busy
                            ? null
                            : () => removeOffline(album),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> removeOffline(OfflineAlbum album) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Usunąć zestaw offline?'),
        content: Text(
          'Pliki języków filmu „${album.video.title}” zostaną usunięte z pamięci aplikacji.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (yes == true) await act(() => state.removeAlbum(album));
  }

  Widget history() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Twoje odsłuchy',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Wyczyść historię',
            onPressed: state.history.isEmpty
                ? null
                : () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Wyczyścić historię?'),
                        content: const Text(
                          'Usunięte zostaną pozycje i oznaczenia odsłuchania.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Anuluj'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Wyczyść'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) await act(state.clearHistory);
                  },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Wróć dokładnie tam, gdzie skończyłeś.',
        style: TextStyle(color: Colors.white54),
      ),
      const SizedBox(height: 16),
      if (state.history.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 70),
          child: Column(
            children: [
              Icon(Icons.history, size: 50, color: mint),
              SizedBox(height: 16),
              Text('Twój pierwszy odsłuch czeka.'),
            ],
          ),
        ),
      for (final h in state.history)
        videoTile(
          VideoItem.fromJson(h),
          subtitle:
              '${h['complete'] == true ? 'Ukończone' : 'W trakcie'} · ${clockText((h['positionMs'] as num).toInt())} / ${clockText((h['durationMs'] as num).toInt())}',
        ),
    ],
  );
}

class ChannelPage extends StatefulWidget {
  final ChannelItem channel;
  final AppState state;
  final Future<void> Function(VideoItem) onSelect;
  const ChannelPage({
    super.key,
    required this.channel,
    required this.state,
    required this.onSelect,
  });
  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  ChannelUploadsList? page;
  List<VideoItem> videos = [];
  bool busy = false, done = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy || done) return;
    setState(() => busy = true);
    try {
      final next = page == null
          ? await widget.state.youtube.uploads(widget.channel)
          : await page!.nextPage().timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        if (next == null) {
          done = true;
        } else {
          page = next;
          final ids = videos.map((v) => v.id).toSet();
          videos.addAll(
            widget.state.youtube.items(next).where((v) => ids.add(v.id)),
          );
        }
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = AppState.friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.channel.name)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Nie każdy film kanału ma dubbing. Dotknij filmu, aby sprawdzić dostępne języki.',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 12),
        for (final v in videos)
          ListTile(
            leading: const Icon(Icons.play_circle_outline, color: mint),
            title: Text(v.title, style: const TextStyle(fontSize: 13)),
            subtitle: Text(clockText(v.durationMs)),
            onTap: () => widget.onSelect(v),
          ),
        if (error != null) Text(error!),
        if (busy) const Center(child: CircularProgressIndicator()),
        if (!busy && !done)
          TextButton(
            onPressed: load,
            child: Text(
              error != null ? 'Spróbuj ponownie' : 'Wczytaj kolejne filmy',
            ),
          ),
      ],
    ),
  );
}

Future<void> shareRecipe(
  BuildContext context,
  ListeningRecipe recipe,
  String title,
) async {
  final key = GlobalKey();
  final link = recipe.encode();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Podziel się swoim sposobem słuchania',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 18),
            RepaintBoundary(
              key: key,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrImageView(
                      data: link,
                      size: 250,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      backgroundColor: Colors.white,
                    ),
                    const Text(
                      'YubblyApp',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'Dwa języki. Jeden rytm.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Udostępnij obraz QR'),
              onPressed: () async {
                try {
                  await WidgetsBinding.instance.endOfFrame;
                  final boundary =
                      key.currentContext!.findRenderObject()
                          as RenderRepaintBoundary;
                  final picture = await boundary.toImage(pixelRatio: 3);
                  final bytes = await picture.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  picture.dispose();
                  final dir = await getTemporaryDirectory();
                  final file = File('${dir.path}/yubbly_recipe.png');
                  await file.writeAsBytes(bytes!.buffer.asUint8List());
                  await SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(file.path)],
                      text: 'YubblyApp · $title\n$link',
                    ),
                  );
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Nie udało się udostępnić obrazu. Skopiuj link poniżej.',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Kopiuj link ustawień'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Skopiowano link ustawień.')),
                  );
                }
              },
            ),
            const Text(
              'Kod zawiera film, języki, pozycję i parametry miksu. Otwórz go skanerem w YubblyApp.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
    ),
  );
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool found = false;
  @override
  void dispose() {
    scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Skanuj kod YubblyApp')),
    body: MobileScanner(
      controller: scanner,
      errorBuilder: (_, error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Brak dostępu do aparatu. Zezwól na aparat w ustawieniach aplikacji lub wklej link ustawień.\n${error.errorCode.name}',
          ),
        ),
      ),
      onDetect: (capture) {
        if (found) return;
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (raw == null) return;
        try {
          ListeningRecipe.decode(raw);
          found = true;
          Navigator.pop(context, raw);
        } catch (_) {
          /* Ignore unrelated QR codes. */
        }
      },
    ),
  );
}

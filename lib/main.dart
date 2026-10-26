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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YubblyApp());
}

const mint = Color(0xff8be8c2),
    amber = Color(0xffffc078),
    panel = Color(0xff18232d);

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
        if (v == 2) act(state.refreshHistory);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.tune), label: 'Odtwarzacz'),
        NavigationDestination(
          icon: Icon(Icons.video_library_outlined),
          label: 'Odkrywaj',
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
                    SizedBox(
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
                                state.playing ? Icons.pause : Icons.play_arrow,
                                size: 32,
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
            mode(MixMode.orbit, 'Płynna zamiana', Icons.sync),
            mode(MixMode.split, 'A lewo · B prawo', Icons.headphones),
            mode(MixMode.mono, 'Naprzemiennie mono', Icons.waves),
            mode(MixMode.together, 'Oba jednocześnie', Icons.merge),
          ],
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
                    subtitle: const Text(
                      'Zmiana wymaga pauzy i ponownego uruchomienia.',
                    ),
                    value: state.withVideo,
                    onChanged: state.playing || state.buffering
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

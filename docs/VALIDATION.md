# Walidacja — 26.10.2026

## Wyniki wykonanych sprawdzeń

| Sprawdzenie | Wynik | Zakres |
|---|---|---|
| `flutter analyze` | PASS — 0 problemów | Kod Dart aplikacji, testy i skrypty diagnostyczne w `tool/` |
| `flutter test` | PASS — 18 testów | Poprawne/błędne linki, QR i jego wersja, limity parametrów, format czasu, katalog/dialog dodawania, przywrócenie sesji i przełączenie trybu miksu na ekranie 390 × 844, a także proxy strumieni (probe 2-bajtowy, cały utwór przez wiele jednorazowych adresów, seek, 416, zakres `range=` dla `ios`, odpowiedzi HTML, zwolnienie sesji) |
| Test Java `MixerMathTest` | PASS — 504 009 asercji | Routing, zamiana uszu, przeciwne fazy, centrowanie mono, skończone i bezpieczne wzmocnienia, granice przesunięcia i kierunek korekty prędkości |
| Wizualna kontrola renderu Flutter | PASS | Wąski ekran odtwarzacza; poprawiono szerokość nagłówka, załadowano font tekstu i ikony do testu |
| YouTube — metadane i ścieżki | PASS dla `zA-UHB2WcT4` | Tytuł, kanał i 10 ścieżek, m.in. `en-US.4` (oryginał) i `pl.10` |
| YouTube — faktyczne dane audio | NIEPOTWIERDZONE | Adresy hostów mediów zwracają w tym środowisku 195-bajtową stronę HTML „Site Unavailable”, także przy statusie HTTP 206. Nie jest to dźwięk i nie uznajemy tego testu za udany. |
| Odsłuch / wygaszony ekran / Bluetooth | NIEWYKONANE | Brak podłączonego urządzenia Android; wymagają sprawdzenia na telefonie |

## Wykryte ścieżki przykładowego filmu

English (US) original, French (FR), German (DE), Hindi, Indonesian, Italian, Japanese, Polish, Portuguese (BR), Spanish (US). Lista jest obserwacją z chwili testu, nie gwarancją niezmiennej dostępności.

## Granice walidacji

Testy matematyki nie dowodzą synchronizacji rzeczywistych dekoderów. Testy widgetów używają kontrolowanej odpowiedzi mostu Androida i nie odtwarzają audio. Render w `test/goldens/player.png` używa demonstracyjnych danych sesji oraz zastępczego obrazu dla miniatury, nie przedstawia rzeczywistego odsłuchu.

Obsługa błędów strumienia odrzuca odpowiedzi HTML, zamiast przedstawiać je jako poprawny dźwięk. Ponowny start po błędzie pobiera świeże adresy. Do odbioru końcowego użyj [DEVICE_CHECKLIST.md](DEVICE_CHECKLIST.md).

## Środowisko budowania

Flutter 3.35.7, Dart 3.9.2, Temurin JDK 17, Android API 36, Media3 1.8.0, Gradle 8.12. Zależności Dart zapisano w `pubspec.lock`. Nie zapisano w paczce lokalnych ścieżek SDK, tymczasowych ustawień sieciowych, tokenów ani podpisanych adresów mediów.

Wersja testowa ma wyłączoną minifikację/shrinking Androida. Pierwsza kompilacja z R8 przeszła, ale zgłosiła niezgodność odczytu metadanych Kotlin nowszych zależności. Aby nie dostarczać niezweryfikowanej optymalizacji, finalny wariant zachowuje te metadane; włączenie optymalizacji wymaga aktualizacji AGP/R8 i kontroli na urządzeniu.

## Dostarczony instalator

- Finalna kompilacja `:app:assembleRelease`: **PASS** (bez minifikacji).
- `apksigner verify --verbose`: **PASS**, podpis APK Signature Scheme v2.
- Pakiet `app.yubbly.yubbly_app`, wersja `0.1.0`, kod wersji wariantu ARM64 `2001`.
- Android API 26+, target API 36; architektura `arm64-v8a`.
- Sprawdzono manifest wynikowego APK, w tym własną obsługę linków QR.
- Instalator: `YubblyApp-0.1.0-arm64.apk` (34046199 bajtów).
- SHA-256: `ca0eadf9bc1ddde1d9ecdb9eb90c02b9db8f07c5ee0de2d4627af85504db5086`.


## Apple audio adapter (26.10.2026)

Środowisko Apple: Flutter 3.47.1, Dart 3.13.1, Xcode 26.5, macOS 26.7.1, symulator iPhone 16 Pro (iOS 18.3).

| Sprawdzenie | Wynik | Zakres |
|---|---|---|
| `flutter analyze` | PASS — 0 problemów | Dart po dodaniu Apple i filtra MP4 |
| `flutter test` | PASS — 18 testów | W tym test akcji **Odśwież** przy błędzie strumienia i testy lokalnego proxy |
| `AppleMixerMathTest.swift` | PASS — 528 009 asercji | Routing, zamiana uszu, mono, granice, korekta prędkości, przesunięcie B |
| `flutter build macos --debug` | PASS | Wspólny silnik AVFoundation + kanał macOS |
| `flutter build ios --debug --no-codesign` | PASS | Target iOS, AppDelegate, kanał i tap |
| `flutter build ios --simulator --debug` | PASS | iPhone 16 Pro (iOS 18.3); aplikacja instaluje się i uruchamia ekran startowy |
| Próba silnika na macOS | PASS | Dwa zdalne strumienie `googlevideo.com` (AAC), `MTAudioProcessingTap` aktywny, stabilny dryf ≈ −21 ms, pozycja i historia zapisywane |
| Koniec materiału | PASS | Pozycja zatrzymana na metadanych YouTube ≈ 19 s mimo 38 s w kontenerze MP4 i ciszy po 19 s |
| Odsłuch na sprzęcie Apple | NIEWYKONANY | Brak testu słuchowego; RMS z tapu potwierdził przetwarzane ramki, ale nie zastępuje odsłuchu |
| iOS w tle / ekran blokady | CZĘŚCIOWO | `UIBackgroundModes: audio` i kategoria `playback`; brak `MPRemoteCommandCenter` |
| Impeller na Apple | PASS | `FLTEnableImpeller` = `false` w `ios/Runner/Info.plist` i `macos/Runner/Info.plist`; Skia/Metal dla Debug, Profile i Release |
| Czytelny błąd 403 | PASS | `CoreMediaErrorDomain -12660` jest rozwijany z łańcucha `NSError`; UI pokazuje HTTP 403 i przycisk **Odśwież** pobierający nowe adresy |
| Długie filmy z dubami | NAPRAWIONE (proxy) | Przyczyną był limit po stronie googlevideo: jeden adres serwuje ~1 MiB, a warianty `ios` przyjmują zakres wyłącznie jako `range=` w zapytaniu. `lib/stream_proxy.dart` dzieli strumień na segmenty 1 MiB, pobiera świeży adres dla każdego segmentu i serwuje graczowi `206 Partial Content`; pokryte testami `test/stream_proxy_test.dart` (probe 2-bajtowy, cały utwór, seek, 416, tryb `ios`, tagi HTML) |
| Dwie ścieżki językowe jednocześnie | PASS (jednostkowo) | Oba adresy pochodzą z tego samego proxy jako `/media/<id>`; `release()` czyści segmenty przy zmianie sesji, `stop()` w `AppState` zwalnia je jawnie |

### Wnioski techniczne

- `MTAudioProcessingTap` działa ze zdalnymi progresywnymi plikami MP4 z googlevideo; format dekodowania to 44,1 kHz, stereo float32 planar.
- `AVPlayer` po `pause`/`seek` startuje audio z opóźnieniem ~0,5 s, a `seek` natychmiast po nim może zostać anulowany przez `preroll`. Silnik czeka na zakończenie obu `seek`, dodaje 200 ms osadzenia i prerolluje oba odtwarzacze.
- Część strumieni YouTube ma błędny czas trwania w kontenerze (dwukrotność) i ciszę na końcu; osią czasu jest `durationMs` z metadanych filmu.
- AVFoundation nie odtwarza WebM/Opus, dlatego iOS/macOS filtrują listę języków do wariantów MP4.
- Strumienie z `gir=yes` serwują w badanym środowisku tylko ograniczony zakres początkowy, a kolejne żądania bajtów kończą się HTTP 403. Obejściem jest lokalne proxy (`lib/stream_proxy.dart`): 1 MiB segmenty, świeży adres do każdego segmentu, normalizacja `Range` (nagłówek → `range=` w zapytaniu), cache na dysku z prefetchem 4 segmentów i sprzątaniem 64 MiB za pozycją odczytu.

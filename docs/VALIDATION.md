# Walidacja — 26.10.2026

## Wyniki wykonanych sprawdzeń

| Sprawdzenie | Wynik | Zakres |
|---|---|---|
| `flutter analyze` | PASS — 0 problemów | Kod Dart aplikacji, testy i skrypty diagnostyczne w `tool/` |
| `flutter build macos --debug` | PASS | Finalny kod offline + lokalne `file://`; aplikacja zbudowana |
| `flutter build apk --debug` | PASS z `--android-skip-build-dependency-validation` | Istniejący wrapper Gradle 8.12 jest niższy niż minimum Fluttera 8.14; kompilacja Java/Media3 i APK przeszła po obejściu walidacji wersji |
| `flutter test` | PASS — 39 testów | Poprawne/błędne linki, QR i jego wersja, limity parametrów, format czasu, katalog/dialog dodawania, przywrócenie sesji i przełączenie trybu miksu na ekranie 390 × 844, proxy strumieni (probe 2-bajtowy, cały utwór przez wiele jednorazowych adresów, odświeżanie wyczerpanego URL-a, seek, 416, zakres `range=` dla `ios`, odpowiedzi HTML, zwolnienie sesji), biblioteka offline (albumy, brakujące pliki, uszkodzony indeks), pobieranie segmentowe (wznawianie, anulowanie, `range=`, odświeżanie adresu po błędzie), lokalne `file://` w moście odtwarzania, parser i wybór ścieżek `WEB_EMBEDDED_PLAYER` oraz most solvera `n` (cache skryptu i ponowna próba) |
| Test Java `MixerMathTest` | PASS — 504 009 asercji | Routing, zamiana uszu, przeciwne fazy, centrowanie mono, skończone i bezpieczne wzmocnienia, granice przesunięcia i kierunek korekty prędkości |
| Wizualna kontrola renderu Flutter | PASS | Wąski ekran odtwarzacza; poprawiono szerokość nagłówka, załadowano font tekstu i ikony do testu |
| YouTube — ścieżki przez `WEB_EMBEDDED_PLAYER` | PASS dla `zA-UHB2WcT4` | Tytuł, kanał i 44 warianty audio / 5 wideo; 10 języków, m.in. `en-US` (oryginał), `pl`, `de-DE`. Osadzony klient wymaga rozwiązania `n` przez player JS. |
| YouTube — faktyczne dane audio | PASS | Po rozwiązaniu `n`: pełny utwór AAC 55 988 121 B pobrany w całości, a obie ścieżki przeszły przez `StreamProxy` (3 MiB każda, zakresy 206). Wcześniejszy błąd „Site Unavailable” dotyczył natywnych adresów z limitem 1 MiB, nie tej ścieżki. |
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
| `flutter test` | PASS — 39 testów | W tym test akcji **Odśwież** przy błędzie strumienia, testy lokalnego proxy, biblioteki offline, odtwarzania lokalnego `file://`, parsera `WEB_EMBEDDED_PLAYER` oraz cache/ponownej próby solvera `n` |
| `AppleMixerMathTest.swift` | PASS — 528 009 asercji | Routing, zamiana uszu, mono, granice, korekta prędkości, przesunięcie B |
| `flutter build macos --debug` | PASS | Wspólny silnik AVFoundation + kanał macOS |
| Solver `n` w ukrytym WKWebView | PASS | `window.__yubblySolveN` zwrócił `eEt1KOdiqaDduA`; w aplikacji `Yubbly web manifest zA-UHB2WcT4: 44 audio, 5 video` |
| `flutter build ios --debug --no-codesign` | PASS | Target iOS, AppDelegate, kanał i tap |
| `flutter build ios --simulator --debug` | PASS | iPhone 16 Pro (iOS 18.3); aplikacja instaluje się i uruchamia ekran startowy |
| Próba silnika na macOS | PASS | Dwa zdalne strumienie `googlevideo.com` (AAC), `MTAudioProcessingTap` aktywny, stabilny dryf ≈ −21 ms, pozycja i historia zapisywane |
| Koniec materiału | PASS | Pozycja zatrzymana na metadanych YouTube ≈ 19 s mimo 38 s w kontenerze MP4 i ciszy po 19 s |
| Odsłuch na sprzęcie Apple | NIEWYKONANY | Brak testu słuchowego; RMS z tapu potwierdził przetwarzane ramki, ale nie zastępuje odsłuchu |
| iOS w tle / ekran blokady | CZĘŚCIOWO | `UIBackgroundModes: audio` i kategoria `playback`; brak `MPRemoteCommandCenter` |
| Impeller na Apple | PASS | `FLTEnableImpeller` = `false` w `ios/Runner/Info.plist` i `macos/Runner/Info.plist`; Skia/Metal dla Debug, Profile i Release |
| Czytelny błąd 403 | PASS | `CoreMediaErrorDomain -12660` jest rozwijany z łańcucha `NSError`; UI pokazuje HTTP 403 i przycisk **Odśwież** pobierający nowe adresy |
| Długie filmy z dubami | PASS po solverze `n` | 26.10.2026: natywny klient nadal kończy zakresy po ~1 MiB na `403`. `WEB_EMBEDDED_PLAYER` + main player JS + ejs w ukrytym WebView daje adresy bez tego limitu; 56 MB utwór pobrał się w całości, a proxy obsłużyło oba języki. |
| Offline — live YouTube | PASS | `live_offline_check` pobrał dwie pełne ścieżki AAC po 55 988 121 B (10 s i 14 s) i potwierdził zgodność rozmiaru. `AudioDownloader` i `OfflineLibrary` zachowują wznawianie i weryfikację rozmiaru. |
| Offline — pełna ścieżka aplikacji | PASS | Smoke `AppState` + prawdziwy WKWebView na macOS: `2lHT74wlnZY` → 54 języki, dwa pliki po 7 149 853 B, następnie odtwarzanie lokalne `file://` (pozycja rosła, brak błędu). Usunięte stare `.part` po 1 MiB nie wróciły. |
| Solver `n` — drugi manifest | PASS | Dwa kolejne pobrania manifestu dla tego samego player URL: 220 i 220 wariantów audio. Skrypt odtwarzacza jest cache'owany natywnie, a odświeżenie manifestu używa tej samej sesji zamiast ponownie pobierać 2,5 MB player JS. |
| Dwie ścieżki językowe jednocześnie | PASS | Oba adresy pochodzą z tego samego proxy jako `/media/<id>`; `release()` czyści segmenty przy zmianie sesji, `stop()` w `AppState` zwalnia je jawnie. |

### Wnioski techniczne

- `MTAudioProcessingTap` działa ze zdalnymi progresywnymi plikami MP4 z googlevideo; format dekodowania to 44,1 kHz, stereo float32 planar.
- `AVPlayer` po `pause`/`seek` startuje audio z opóźnieniem ~0,5 s, a `seek` natychmiast po nim może zostać anulowany przez `preroll`. Silnik czeka na zakończenie obu `seek`, dodaje 200 ms osadzenia i prerolluje oba odtwarzacze.
- Część strumieni YouTube ma błędny czas trwania w kontenerze (dwukrotność) i ciszę na końcu; osią czasu jest `durationMs` z metadanych filmu.
- AVFoundation nie odtwarza WebM/Opus, dlatego iOS/macOS filtrują listę języków do wariantów MP4.
- Strumienie natywnego klienta z `gir=yes` nadal serwują tylko pierwszy ~1 MiB. `WEB_EMBEDDED_PLAYER` zwraca osobne adresy dla każdej wersji językowej, ale wymaga przeliczenia `n` przez player JS. Solver ejs działa w ukrytym WebView (macOS/iOS/Android); po podmianie `n` serwer odpowiada `206` dla dowolnego zakresu. Z tego powodu proxy i `AudioDownloader` nie są już ograniczone limitem 1 MiB, a pobranie 56 MB utworu zakończyło się zgodnym rozmiarem.
- Offline: `AudioDownloader` używa normalizacji `Range` i mintuje świeży adres dla każdego segmentu 1 MiB, zapisuje wynik do trwałego `.part`, weryfikuje rozmiar i dopiero potem zmienia nazwę na docelową. Po odrzuceniu segmentu ponowna próba używa `refreshMint` i pobiera nowy manifest, zamiast w kółko dostawać ten sam wyczerpany URL. `OfflineLibrary` trzyma jeden album na film i dowolną liczbę języków; brak pliku usuwa wpis przy starcie. Odtwarzanie kompletnej pary A+B przekazuje do AVPlayer/ExoPlayer `file://` i nie tworzy proxy.
- Wybór offline preferuje MP4/AAC i wariant o bitrate najbliższym 128 kbps. To nie jest konwersja do MP3: YouTube nie udostępnia strumieni MP3. Prawdziwy eksport MP3 wymaga osobnego dekodera AAC/Opus i enkodera LAME.

# Walidacja — 26.10.2026

## Wyniki wykonanych sprawdzeń

| Sprawdzenie | Wynik | Zakres |
|---|---|---|
| `flutter analyze` | PASS — 0 problemów | Kod Dart aplikacji, testy i narzędzie sprawdzające YouTube |
| `flutter test` | PASS — 9 testów | Poprawne/błędne linki, QR i jego wersja, limity parametrów, format czasu, katalog/dialog dodawania, przywrócenie sesji i przełączenie trybu miksu na ekranie 390 × 844 |
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

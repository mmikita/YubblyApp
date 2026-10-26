# YubblyApp

Aplikacja Flutter na **Androida 8.0+**, **iOS 15+** i **macOS 12+** do słuchania dwóch ścieżek językowych jednego filmu YouTube. Bez osobnego serwera. Audio można odtwarzać strumieniowo albo pobrać jako zestaw offline M4A/AAC ~128 kbps.

## Szybki start

1. Otwórz **Odkrywaj** i wybierz film z katalogu lub wklej link YouTube przyciskiem `+`.
2. Poczekaj na sprawdzenie rzeczywiście dostępnych ścieżek audio. Wybierz język A i B.
3. Wybierz sposób słuchania, załóż słuchawki i naciśnij Odtwórz. Możesz też nacisnąć **Pobierz A+B**, aby zapisać oba języki lokalnie i słuchać bez sieci.
4. Pobrane zestawy są widoczne w **Bibliotece**: jeden film, wiele języków, rozmiar i przycisk „Dodaj język”. Pliki M4A/AAC ~128 kbps zostają w pamięci aplikacji.
5. Prędkość 1–5×, głośność i ustawienia miksu zmieniają się na żywo. Aby zmienić języki lub włączyć obraz, najpierw wstrzymaj odtwarzanie.
6. Na Androidzie po zminimalizowaniu używaj powiadomienia/ekranu blokady. Na iOS i macOS dźwięk działa w tle (iOS ma kategorię `playback`), ale ekran blokady iOS nie ma jeszcze własnych przycisków sterowania. Przycisk Stop zatrzymuje odtwarzanie w tle.
7. **Udostępnij** tworzy obraz QR z podpisem YubblyApp albo link ustawień. Znajomy skanuje go w aplikacji.

Film bez co najmniej dwóch wykrytych ścieżek nie jest przedstawiany jako gotowy do dwujęzycznego odtwarzania. Napisy nie są zamiennikiem dubbingu. Oryginał oznaczamy tylko wtedy, gdy określa go nazwa ścieżki zwrócona przez YouTube; domyślna ścieżka może być dubbingiem.

## Funkcje

- Dwa niezależne strumienie audio i opcjonalny obraz do 720p (obraz tylko na Androidzie; iOS i macOS odtwarzają samo audio).
- Biblioteka offline: po wyborze języków pobiera pełne pliki M4A/AAC ~128 kbps, grupuje je pod jednym filmem i pozwala dociągnąć kolejne języki. Gdy komplet A+B jest lokalny, odtwarzanie nie używa sieci ani proxy. W obecnym środowisku YouTube może blokować pełny zakres — patrz „Granice tej wersji”.
- Tryby zgodne z Wiki: `split-ear` (A lewo / B prawo), `dual-combo` (sinusoidalna zamiana stron w obu uszach), `mono-combo` (oba w centrum) oraz dodatkowy stały miks.
- Długość cyklu 2–300 s, krzywa equal-power/liniowa, kontrast, faza, mikromodulacja, zamiana uszu i korekta czasu ±3 s.
- Sterowanie z powiadomienia, obsługa utraty audio focus, odłączenia słuchawek, buforowania i wspólnego przewijania.
- Historia z pozycją i oznaczeniem ukończenia, przywrócenie ostatniej sesji, ulubione, dodawanie/usuwanie filmów i kanałów.
- Katalog startowy: **26 filmów i 32 kanały**, z repozytorium/Wiki/dyskusji Youbbly; przeglądanie kolejnych stron filmów kanału wewnątrz aplikacji.
- QR PNG, udostępnianie linku, skaner QR, obsługa linków `yubbly://` oraz funkcji „Udostępnij” z YouTube.
- Brak własnych reklam i brak ładowania reklamowego odtwarzacza YouTube. Segmenty sponsorowane będące częścią filmu pozostają.

## Budowanie

Wymagane: Flutter **3.47.1 / Dart 3.13.1**, JDK 17, Android SDK z platformą 36 i narzędziami wskazanymi przez Flutter. Na Windowsie najłatwiej zainstalować Android Studio i Flutter SDK, dodać Flutter do PATH, a następnie:

```sh
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter run
```

APK dla telefonów 64-bit ARM:

```sh
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Wynik: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. Pozostałe architektury można zbudować przez `flutter build apk --release --split-per-abi`.

Ta wersja testowa nie minifikuje kodu Androida: zachowuje metadane zależności Kotlin/ML Kit. Konfiguracja podpisuje kompilację release **kluczem deweloperskim debug**. Do publikacji i trwałych aktualizacji trzeba skonfigurować własny keystore. Projekt zawiera [workflow GitHub Actions](https://github.com/mmikita/YubblyApp/actions) uruchamiany ręcznie lub przy push/PR do main. Po pomyślnym wykonaniu APK są dostępne w artefakcie `YubblyApp-Android` danego uruchomienia.

### iOS i macOS

Oba targety Apple korzystają ze wspólnego silnika AVFoundation w `apple/YubblyPlaybackEngine.swift`. Wymagają Xcode 16+ (sprawdzane z Xcode 26.5) i Fluttera 3.47.1:

```sh
flutter pub get
flutter run -d macos
# lub, po uruchomieniu symulatora:
flutter run -d "iPhone 17 Pro"
flutter build ios --simulator --debug
```

iOS wymaga MP4/AAC dla obu ścieżek — AVFoundation nie odtwarza strumieni WebM/Opus z YouTube. Lista języków jest filtrowana do ścieżek z MP4, a przy braku takiego strumienia aplikacja pokazuje czytelny błąd. Obraz wideo jest dostępny tylko na Androidzie.

Renderowanie na macOS i iOS korzysta ze Skii (Metal), nie z Impellera: w `macos/Runner/Info.plist` i `ios/Runner/Info.plist` jest ustawione `FLTEnableImpeller` = `false` dla wszystkich konfiguracji (Debug, Profile, Release). Impeller powodował artefakty graficzne przy przełączaniu widoków. Nie zmienia to Androida.

Silnik Apple:

- Trzyma dwa niezależne `AVPlayer` — A i B — i miksuje ich wyjścia w systemowym mikserze.
- Do każdej ścieżki podłącza `MTAudioProcessingTap`, który sprowadza dźwięk do mono i rozprowadza go do lewej/prawej według tej samej macierzy i wygładzania 10 ms co Android.
- Synchronizuje pozycje przez `preroll` obu graczy przed startem i po przewinięciu, korektę tempa B do ±2,5% oraz twardą korektę przez wspólne przewinięcie, gdy dryf przekracza 150 ms.
- Zapisuje sesję, pozycję i historię w `UserDefaults`, niezależnie od `shared_preferences` interfejsu.
- Na iOS ustawia `AVAudioSession` w kategorii `playback`, obsługuje przerwania i odłączenie słuchawek oraz dodaje `UIBackgroundModes: audio`.

Znane ograniczenia targetów Apple:

- **Tylko audio.** Obraz jest dostępny wyłącznie na Androidzie; przełącznik „Odtwarzaj również obraz” jest na macOS/iOS wyłączony, a ekran pokazuje miniaturę.
- **Tylko MP4/AAC.** AVFoundation nie odtwarza WebM/Opus. Jeśli wybrana ścieżka nie ma wariantu MP4, odtwarzanie kończy się komunikatem zamiast cichego błędu.
- **Brak przycisków na ekranie blokady iOS.** Dźwięk gra w tle dzięki `UIBackgroundModes: audio` i kategorii `playback`, ale `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` nie są jeszcze podłączone.
- **Brak rejestracji schematu `yubbly://` na iOS.** Kody QR działają przez skaner w aplikacji; otwieranie linków z innych aplikacji nie jest jeszcze podłączone.
- **AirPlay.** `MTAudioProcessingTap` nie jest stosowany w strumieniu AirPlay, więc routing lewo/prawo może być wtedy nieaktywny.
- **Czas trwania.** Część strumieni YouTube ma w kontenerze MP4 dwukrotnie dłuższy czas niż materiał i końcową ciszę. Silnik używa czasu trwania filmu z YouTube do osi czasu, przewijania i wykrycia końca.
- Historia, katalog, sprawdzanie ścieżek, udostępnianie, skaner QR i ustawienia miksu działają normalnie. Historia zapisuje się w `UserDefaults` podczas rzeczywistego odtwarzania.

## Testy

```sh
flutter analyze
flutter test
bash tool/test_native.sh
# Opcjonalny test sieciowy (bez zapisu mediów):
dart run tool/probe_youtube.dart zA-UHB2WcT4
# Opcjonalny test end-to-end lokalnego proxy na prawdziwych adresach YouTube:
dart run tool/live_proxy_check.dart zA-UHB2WcT4
# Pełny pobór dwóch ścieżek (wymaga Node.js — solver `n`):
dart run tool/live_offline_check.dart zA-UHB2WcT4
```

`test_native.sh` uruchamia test Javy, jeśli dostępne są `javac` i `java` (na Windowsie można użyć Git Bash), a na macOS dodatkowo kompiluje test matematyki miksera Apple, jeśli dostępny jest `swiftc`. Testy obejmują walidację linków i QR, przywracanie stanu/interfejs na małym ekranie, obsługę sterowania, matematykę routingu/bezpiecznych poziomów sygnału oraz lokalne proxy strumieni (`test/stream_proxy_test.dart`: 2-bajtowy probe, cały utwór, seek, 416, adresy `ios` z zakresem w zapytaniu, odpowiedzi HTML). `tool/live_proxy_check.dart` dodatkowo czyta kilka megabajtów prawdziwych ścieżek przez pętlę zwrotną, a `tool/probe_youtube.dart` sprawdza metadane i początkowe fragmenty obu ścieżek.

Szczegółowy wynik walidacji tej paczki: [docs/VALIDATION.md](docs/VALIDATION.md). Kontrola na telefonie: [docs/DEVICE_CHECKLIST.md](docs/DEVICE_CHECKLIST.md).

## Granice tej wersji

- Platforma odtwarzania: Android (Media3) oraz iOS/macOS (AVFoundation, audio). Adaptery Windows/Web nie są zaimplementowane. Offline zapisuje M4A/AAC ~128 kbps; eksport prawdziwego MP3 (wymagający dekodera AAC/Opus i enkodera LAME) jest osobnym, przyszłym krokiem.
- YouTube jest odczytywany przez nieoficjalny ekstraktor `youtube_explode_dart` 3.1.0. Zmiany YouTube, blokady regionalne, ograniczenia wieku lub wygasłe adresy mogą wymagać ponownego pobrania strumieni/aktualizacji biblioteki.
- Adresy `googlevideo.com` z klienta natywnego w badanym środowisku (26.10.2026) serwują tylko pierwszy ~1 MiB. Aplikacja używa więc najpierw `WEB_EMBEDDED_PLAYER`, który zwraca bezpośrednie URL-e dla wszystkich ścieżek językowych. Parametr `n` jest rozwiązywany przez wbudowany solver yt-dlp/ejs w ukrytym WebView (macOS/iOS/Android); po podmianie `n` zakresy działają bez limitu — sprawdzono pobranie dwóch pełnych utworów po 56 MB i strumieniowanie obu ścieżek przez lokalne proxy. Gdy solver lub osadzony klient jest niedostępny, repozytorium wraca do klienta natywnego. Proxy wymaga dopuszczenia HTTP do pętli zwrotnej: `NSAllowsLocalNetworking` w `ios/Runner/Info.plist` i `macos/Runner/Info.plist` oraz `android/app/src/main/res/xml/network_security_config.xml` (reszta ruchu pozostaje HTTPS-only).
- Proxy działa w izolacie Fluttera, więc odtwarzanie w tle zależy od życia procesu aplikacji: na Androidzie usługa pierwszoplanowa gra dalej, ale po zabiciu procesu (lub zniszczeniu `FlutterEngine` przez system) strumień się kończy i trzeba go wznowić ręcznie.
- Dwie ścieżki mają wspólną pozycję czasową z korektą dryfu, lecz nie są jednym mikserem próbek ze wspólnym zegarem sprzętowym. Jakość synchronizacji, Bluetooth, AirPlay, 5× i długie odtwarzanie z wygaszonym ekranem należy potwierdzić na urządzeniu.
- Aplikacja nie blokuje reklam w innych aplikacjach ani w przeglądarce. Pobiera strumienie samego materiału; nie wycina fragmentów sponsorskich zapisanych w treści.
- Wymuszone zatrzymanie aplikacji przez system kończy odtwarzanie. Po restarcie odtwarzanie jest wznawiane ręcznie; dla pobranego zestawu A+B wystarczy otworzyć album w Bibliotece i nie trzeba rozwiązywać adresów YouTube.

## Źródła i konstrukcja

Pomysł i lista materiałów: [KuuuGR/Youbbly](https://github.com/KuuuGR/Youbbly), [Wiki](https://github.com/KuuuGR/Youbbly/wiki), [Discussion #2](https://github.com/KuuuGR/Youbbly/discussions/2). Lista pobrana 26.10.2026; tytuły i kanały dla 24 filmów rozwiązano przez YouTube oEmbed, dwa przykłady zachowują opis z README źródła. Dostępność języków jest zawsze sprawdzana przy otwarciu.

Nie skopiowano skryptów Pythona. Routing rozróżnia tryby zgodnie z opisem Wiki; naprawia niezgodność identycznych wag `dual-combo` i `mono-combo` w skrypcie referencyjnym. Więcej: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

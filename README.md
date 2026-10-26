# YubblyApp

Aplikacja Flutter na **Androida 8.0+** do słuchania dwóch ścieżek językowych jednego filmu YouTube. Bez osobnego serwera i bez pobierania całego filmu na dysk przed odtwarzaniem.

## Szybki start

1. Otwórz **Odkrywaj** i wybierz film z katalogu lub wklej link YouTube przyciskiem `+`.
2. Poczekaj na sprawdzenie rzeczywiście dostępnych ścieżek audio. Wybierz język A i B.
3. Wybierz sposób słuchania, załóż słuchawki i naciśnij Odtwórz.
4. Prędkość 1–5×, głośność i ustawienia miksu zmieniają się na żywo. Aby zmienić języki lub włączyć obraz, najpierw wstrzymaj odtwarzanie.
5. Po zminimalizowaniu używaj powiadomienia/ekranu blokady. Przycisk Stop zatrzymuje także odtwarzanie w tle.
6. **Udostępnij** tworzy obraz QR z podpisem YubblyApp albo link ustawień. Znajomy skanuje go w aplikacji.

Film bez co najmniej dwóch wykrytych ścieżek nie jest przedstawiany jako gotowy do dwujęzycznego odtwarzania. Napisy nie są zamiennikiem dubbingu. Oryginał oznaczamy tylko wtedy, gdy określa go nazwa ścieżki zwrócona przez YouTube; domyślna ścieżka może być dubbingiem.

## Funkcje

- Dwa niezależne strumienie audio i opcjonalny obraz do 720p.
- Stały podział A/lewo i B/prawo, sinusoidalna zamiana stron, naprzemienny miks mono oraz oba języki jednocześnie.
- Długość cyklu 2–300 s, krzywa equal-power/liniowa, kontrast, faza, mikromodulacja, zamiana uszu i korekta czasu ±3 s.
- Sterowanie z powiadomienia, obsługa utraty audio focus, odłączenia słuchawek, buforowania i wspólnego przewijania.
- Historia z pozycją i oznaczeniem ukończenia, przywrócenie ostatniej sesji, ulubione, dodawanie/usuwanie filmów i kanałów.
- Katalog startowy: **26 filmów i 32 kanały**, z repozytorium/Wiki/dyskusji Youbbly; przeglądanie kolejnych stron filmów kanału wewnątrz aplikacji.
- QR PNG, udostępnianie linku, skaner QR, obsługa linków `yubbly://` oraz funkcji „Udostępnij” z YouTube.
- Brak własnych reklam i brak ładowania reklamowego odtwarzacza YouTube. Segmenty sponsorowane będące częścią filmu pozostają.

## Budowanie

Wymagane: Flutter **3.35.7 / Dart 3.9.2**, JDK 17, Android SDK z platformą 36 i narzędziami wskazanymi przez Flutter. Na Windowsie najłatwiej zainstalować Android Studio i Flutter SDK, dodać Flutter do PATH, a następnie:

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

### macOS (podgląd interfejsu)

Projekt zawiera target macOS do kompilacji i uruchamiania interfejsu na komputerze:

```sh
flutter pub get
flutter run -d macos
```

Silnik odtwarzania nadal istnieje wyłącznie dla Androida. Na macOS działają katalog, sprawdzanie dostępnych ścieżek, QR, udostępnianie i ekran historii (wpisy powstają w trakcie odtwarzania, więc na macOS pozostaje pusty), a naciśnięcie Odtwórz pokazuje komunikat o braku adaptera audio zamiast błędu kanału platformy. Okno ma minimalny rozmiar 360×640, a skaner QR wymaga zgody na dostęp do kamery.

Renderowanie na macOS korzysta ze Skii (Metal), nie z Impellera: w `macos/Runner/Info.plist` jest ustawione `FLTEnableImpeller` = `false` dla wszystkich konfiguracji (Debug, Profile, Release). Impeller na macOS powodował artefakty graficzne przy przełączaniu widoków. Nie zmienia to Androida ani iOS.

Znane ograniczenia targetu macOS:

- **Brak odtwarzania dźwięku.** Silnik Media3 istnieje tylko na Androidzie. Kanał `app.yubbly/player` odpowiada na `load` i `play` błędem `PlatformException(UNSUPPORTED_PLATFORM)` z komunikatem „Odtwarzanie audio na macOS nie jest jeszcze zaimplementowane…”, a interfejs pokazuje informację o braku adaptera audio zamiast uruchamiać odtwarzanie.
- Historia odtwarzania pozostaje pusta, ponieważ wpisy powstają wyłącznie w trakcie rzeczywistego odtwarzania.
- Katalog, sprawdzanie dostępnych ścieżek, udostępnianie, skaner QR i ustawienia miksu działają normalnie.

## Testy

```sh
flutter analyze
flutter test
bash tool/test_native.sh
# Opcjonalny test sieciowy (bez zapisu mediów):
dart run tool/probe_youtube.dart zA-UHB2WcT4
```

`test_native.sh` wymaga `javac` i `java`; na Windowsie można użyć Git Bash. Testy obejmują walidację linków i QR, przywracanie stanu/interfejs na małym ekranie, obsługę sterowania oraz matematykę routingu/bezpiecznych poziomów sygnału. Test sieciowy próbuje jednocześnie odczytać początkowy fragment angielskiej i polskiej ścieżki.

Szczegółowy wynik walidacji tej paczki: [docs/VALIDATION.md](docs/VALIDATION.md). Kontrola na telefonie: [docs/DEVICE_CHECKLIST.md](docs/DEVICE_CHECKLIST.md).

## Granice tej wersji

- Platforma odtwarzania: Android. Target macOS uruchamia interfejs i funkcje sieciowe, lecz nie ma adaptera audio. Adaptery iOS/Windows/Web oraz opcjonalny eksport gotowego MP3 do odsłuchu offline nie są zaimplementowane.
- YouTube jest odczytywany przez nieoficjalny ekstraktor `youtube_explode_dart` 3.1.0. Zmiany YouTube, blokady regionalne, ograniczenia wieku lub wygasłe adresy mogą wymagać ponownego pobrania strumieni/aktualizacji biblioteki.
- Dwie ścieżki mają wspólną pozycję czasową z korektą dryfu, lecz nie są jednym mikserem próbek ze wspólnym zegarem sprzętowym. Jakość synchronizacji, Bluetooth, 5× i długie odtwarzanie z wygaszonym ekranem należy potwierdzić na urządzeniu.
- Aplikacja nie blokuje reklam w innych aplikacjach ani w przeglądarce. Pobiera strumienie samego materiału; nie wycina fragmentów sponsorskich zapisanych w treści.
- Wymuszone zatrzymanie aplikacji przez Androida kończy odtwarzanie. Po restarcie odtwarzanie jest wznawiane ręcznie, z ponownie rozwiązanymi adresami.

## Źródła i konstrukcja

Pomysł i lista materiałów: [KuuuGR/Youbbly](https://github.com/KuuuGR/Youbbly), [Wiki](https://github.com/KuuuGR/Youbbly/wiki), [Discussion #2](https://github.com/KuuuGR/Youbbly/discussions/2). Lista pobrana 26.10.2026; tytuły i kanały dla 24 filmów rozwiązano przez YouTube oEmbed, dwa przykłady zachowują opis z README źródła. Dostępność języków jest zawsze sprawdzana przy otwarciu.

Nie skopiowano skryptów Pythona. Routing rozróżnia tryby zgodnie z opisem Wiki; naprawia niezgodność identycznych wag `dual-combo` i `mono-combo` w skrypcie referencyjnym. Więcej: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

# Narzędzia diagnostyczne

Skrypty w tym katalogu sprawdzają zachowanie YouTube i ścieżek mediów. Nie są
częścią aplikacji ani instalatora; wymagają sieci i działają w czystym Dart VM
(`dart run tool/<skrypt>.dart`). Nie zapisują danych uwierzytelniających ani
treści mediów, jedynie logują statusy HTTP i nagłówki.

| Skrypt | Do czego służy |
|---|---|
| `probe_youtube.dart` | Metadane filmu i początkowe fragmenty angielskiej i polskiej ścieżki. |
| `live_proxy_check.dart` | End-to-end: wybiera dwie ścieżki jak repozytorium i czyta kilka megabajtów przez `StreamProxy`. |
| `probe_403.dart`, `probe_range.dart`, `probe_headers.dart` | Treść i nagłówki odpowiedzi `403` oraz warianty zakresów bajtów. |
| `probe_clients.dart`, `probe_client_window.dart`, `probe_player.dart`, `probe_dash*.dart`, `probe_hls*.dart` | Zachowanie klientów YouTube: zakresy, manifesty DASH/HLS, segmenty. |
| `probe_audio.dart`, `probe_tracks.dart`, `probe_dubbed.dart`, `probe_muxed.dart`, `probe_vr.dart` | Wybór i dostępność ścieżek audio, obrazu oraz wersji z dubami. |
| `probe_budget.dart`, `probe_segmented.dart`, `probe_sq*.dart`, `probe_refill.dart` | Limit ~1 MiB na adres, segmenty i ponowne pobieranie po wygaśnięciu adresu. |
| Pozostałe `probe_*.dart` | Jednorazowe eksperymenty z sesji diagnozującej limit `googlevideo`; mogą przestać działać po zmianach YouTube lub `youtube_explode_dart`. |

Uwaga: część macierzy klientów używa API oznaczonych w bibliotece jako
przestarzałe (`deprecated_member_use`) — są tam celowo, żeby sprawdzić, czy
nadal zwracają użyteczne adresy.

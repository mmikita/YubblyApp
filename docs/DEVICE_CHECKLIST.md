# Android device acceptance checks

These checks require a physical Android phone or emulator and are not replaced by widget/unit tests.

1. Install the development APK on Android 8+; open a suggested video such as `zA-UHB2WcT4`. Confirm the actual audio-track list includes the desired languages.
2. Select English (original) and Polish. Listen to split mode with headphones, one earpiece at a time. Reverse the ears. Check both channels contain the intended language and no channel bleed.
3. Select the orbit, mono and simultaneous modes. Confirm they differ. Check cycle duration at 1× and 2×, then check pitch and intelligibility at 5×.
4. Seek forward/back repeatedly, including near the start with ±3 s offsets. Introduce temporary network loss. Confirm both tracks pause for buffering and recover together without one continuing alone.
5. Select two languages and press **Pobierz A+B**. Confirm progress, cancel and retry-resume. After completion enable airplane mode, open **Biblioteka → Odtwórz offline**, seek, change modes and confirm playback uses only local files. Add a third language, verify the album shows it, then delete one track and the whole album. Confirm storage is released.
6. Switch apps and lock the screen for at least 15 minutes. Use lock-screen/headset play, pause, seek and stop. Unplug headphones and accept an incoming call. Confirm neither language continues alone.
7. Close/reopen the Activity while playback is active. Then stop playback and force-stop/relaunch the app. Confirm session metadata and position restore; force-stop is expected to stop all audio and requires a manual new play.
8. Enable video, check lip timing and stereo audio, then return to audio-only mode. Check rotation and small-screen layout.
9. Add a channel handle, a video URL, a Shorts URL and an invalid/lookalike URL. Browse more than one page of channel uploads. Confirm unavailable dubbing is explained without fabricated tracks.
10. Share QR PNG to a second device. Confirm the printed YubblyApp label, scan, settings, exact track variant, and position. Try a malformed QR and one with unavailable tracks.
11. Confirm history updates after background listening, favorites persist, and catalog deletion does not remove unrelated items. Test clear history while paused.
12. Test a stream URL expiration by leaving playback paused for hours; retry should resolve fresh streams after a player error.
13. Confirm no YouTube ad-player requests are present; sponsor content embedded into the film is expected to remain.
14. On each platform, confirm the language list stays populated after a cold start and that no visible WebView/page flashes while resolving a film. A hidden WebView is expected only briefly for the `n` signature; it must never request or display video.

Record phone model, Android version, wired/Bluetooth output, video ID, language IDs and observed maximum drift when signing off playback quality. Do not publish signed media URLs in logs.

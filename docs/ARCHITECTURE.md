# YubblyApp — architecture and implementation notes

## Scope

Flutter UI and Dart domain/data code with three native playback targets: Android 8.0+ (API 26) via Media3, plus iOS 15+ and macOS 12+ via a shared AVFoundation engine in `apple/YubblyPlaybackEngine.swift`. Android registers its channel from `MainActivity`; Apple targets register the same `app.yubbly/player` channel through `ApplePlaybackChannel` (macOS via `MacPlaybackChannel`, iOS via `AppDelegate`). macOS and iOS render through Skia on Metal because their `Info.plist` files set `FLTEnableImpeller` to `false`; Impeller produced graphical glitches when switching views. No server, API key, YouTube account, WebView, or permanent media cache. Windows and browser playback adapters are not implemented. Optional offline MP3 export is not implemented in this version.

## Data flow

1. `YoutubeRepository` resolves a video, fetches audio manifests, groups by full track identifier, and preserves YouTube's display labels.
2. `AppState` stores the selected video, two track IDs, listening position, and `MixSettings`.
3. Starting playback resolves separate fresh manifests for A and B. A third fresh manifest is requested only for video mode. Signed stream URLs stay in memory and are excluded from QR codes, history, and disk preferences.
4. `PlaybackService` owns two ExoPlayers independently of Flutter's Activity. Each uses a PCM audio processor to downmix its input and route it into stereo. Android sums their outputs.
5. On iOS/macOS, `ApplePlaybackEngine` owns two `AVPlayer`s. Each `AVPlayerItem` gets an `AVMutableAudioMix` whose `MTAudioProcessingTap` performs the same downmix and stereo routing; AVFoundation sums the two player outputs. `AVAudioSession` (iOS, category `playback`) handles background audio and interruptions.
6. A MediaSession exposes play, pause, seek, speed and stop through paired commands. MediaSessionService supplies the playback notification/foreground lifecycle. Wake mode is network-aware; audio focus and unplugged headphones pause both streams. The Apple channel exposes the same commands to Flutter.
7. Native history writes every five seconds while a session is loaded and on pause/stop/destruction. Flutter can close without becoming responsible for persisting playback progress. At most the most recent five seconds may be lost on an abrupt process kill. Apple stores the session, position and history in `UserDefaults`.

## Mixing

Let `t` be the media position in seconds and `T` the full cycle length:

`u = (1 + sin(2πt/T + phase))/2`.

Linear crossfade uses `a = 1-u`, `b = u`; equal-power uses `a = cos(πu/2)`, `b = sin(πu/2)`. Contrast raises each envelope to a configurable exponent followed by sum/power normalization. Optional opposing micro-modulation is bounded to 50%. Constant conservative headroom prevents correlated sources from clipping after summation.

| UI mode | A → L/R | B → L/R |
|---|---|---|
| A lewo · B prawo | 1, 0 | 0, 1 |
| Płynna zamiana | a, b | b, a |
| Naprzemiennie mono | a, a | b, b |
| Oba jednocześnie | 0.5, 0.5 | 0.5, 0.5 |

Here a/b include micro-modulation and headroom. The period is measured in source media time: at 2× speed a 60-second cycle takes 30 real seconds. Per-sample smoothing of gain changes uses a 10 ms time constant. Master volume is applied equally to both players.

Android applies the matrix in a Media3 `AudioProcessor`. Apple applies the same math inside one `MTAudioProcessingTap` per `AVPlayerItem`, handling planar/interleaved float32 or int16 buffers. The tap folds each source to mono before routing, so both platforms deliberately discard the source's own stereo image.

The reference Python implementation and Wiki disagree in routing. In commit `14dde9b04e04f18506e5b65dcf1d753b2db070ee`, `dual-combo` and `mono-combo` compute identical L/R sums after variable reassignment. The app implements the distinct intended Wiki modes and an additional fixed simultaneous blend, instead of reproducing this bug. It also makes split-ear constant, rather than periodically reducing both ears together.

## Synchronization and limits

Both players wait at a readiness barrier. Seeking updates both positions. Drift is checked every 40 ms against `positionB = max(0, positionA + offsetMs)`. Beyond 25 ms, a bounded ±2.5% temporary speed correction adjusts B. Beyond 150 ms, with a 1.5-second cooldown, both players are paused, reseeked and resumed. For a negative offset near the start, B remains paused and muted until its timeline begins. Playback ends when either stream ends.

Apple adds two AVFoundation-specific constraints. First, pause/resume adds roughly 0.5 s of audio startup latency; `preroll(atRate:)` on both players hides it, and seeks wait for both completion handlers before prerolling. Without those steps, every correction would restart the lag. Second, some YouTube MP4 audio streams declare a doubled container duration followed by silence; the Apple engine therefore uses the video duration from YouTube metadata for the timeline, seek clamp and end detection, falling back to the item duration when metadata is absent.

This is media-time synchronization of two native players, not a sample-locked single-device DSP mixer. Actual drift depends on device decoders/audio output and must be measured on hardware. Differently translated sentences do not align word for word; a manual ±3 s offset is available. The Python project's waveform-correlation auto-alignment is not copied into live playback.

## YouTube behavior

`youtube_explode_dart` 3.1.0 is pinned. The app uses regular audio-only progressive streams and optional video-only MP4 ≤720p. Fragment-only/HLS formats are currently excluded. This can reduce the list on some videos. Library extraction can fail for private, age-restricted, geo-blocked, live, or otherwise unavailable content. It can also fail when YouTube changes extraction requirements. Errors are presented without silently replacing a selected language.

On iOS/macOS `AppState.requiresMp4Audio` filters the language list to tracks that have an MP4 stream, because AVFoundation cannot decode YouTube's WebM/Opus variants. Android still falls back to WebM when no MP4 variant exists.

YouTube's `audioIsDefault` is displayed as “domyślna”; it is not treated as proof of original audio. The original designation is retained when it appears in the returned track name.

The native player requests content streams and does not load YouTube's advertising player or ad requests. This is not a general blocker for the YouTube app/browser and does not remove sponsor segments embedded by creators. No account/cookie or paid-access bypass is implemented.

## Persistence and sharing

- Flutter SharedPreferences: editable catalog, favorites, most recent mix preferences.
- Android private SharedPreferences: last session, media position, up to 500 history records, listened time and completed marker. Android backup is disabled.
- Apple `UserDefaults`: the same session/position/history record under `yubbly.playback.*`; history from the old macOS stub key is migrated when present.
- iOS `Info.plist` declares `UIBackgroundModes: audio`; the audio session uses category `playback` so sound continues with the screen locked. Lock-screen metadata/remote commands are not implemented yet.
- QR schema: `yubbly://listen?v=1&d=<base64url JSON>` with video ID, track IDs, media position, and mix settings. Payloads are size-limited and validated; numerical values are clamped. No media URL, credentials, or user identifiers are shared.
- Native stream bridge accepts only HTTPS `googlevideo.com` destinations supplied by the resolver. User inputs accept only actual YouTube hosts, not lookalike hostnames.
- The custom scheme supports app opening from compatible scanners; the in-app QR scanner also validates the versioned payload. Imported settings never autoplay.

## Source attribution

Product concept, mathematical envelope behavior, and community source list: KuuuGR's [Youbbly](https://github.com/KuuuGR/Youbbly), [Wiki](https://github.com/KuuuGR/Youbbly/wiki), and [Discussion #2](https://github.com/KuuuGR/Youbbly/discussions/2), retrieved 2026-10-26. Wiki commit: `753da1ae410414c882db7c38af66fa215ee15d18`.

This project is an independent implementation; the Python scripts are not bundled. The reference repository did not declare a license at review time. Package licenses remain applicable to their respective dependencies. The bundled Roboto/Material Icons test fonts retain their license files.

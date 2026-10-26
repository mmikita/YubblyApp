import FlutterMacOS

/// Thin macOS adapter around the shared AVFoundation playback engine.
/// The implementation lives in `apple/YubblyPlaybackEngine.swift` so the
/// macOS and iOS targets run exactly the same mixer and synchronization code.
final class MacPlaybackChannel {
  private let playback: ApplePlaybackChannel

  init(messenger: FlutterBinaryMessenger) {
    playback = ApplePlaybackChannel(messenger: messenger)
  }
}

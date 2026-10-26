import FlutterMacOS

/// macOS bridge for the shared `app.yubbly/player` channel.
///
/// The audio engine in this project is implemented only for Android
/// (`PlaybackService` with Media3). Keeping the channel registered on macOS
/// makes the Flutter UI fully usable for browsing the catalog, resolving
/// YouTube track availability, QR sharing and history, instead of failing with
/// `MissingPluginException` on every platform call. Starting playback reports
/// an explicit error because no desktop mixer exists yet.
final class MacPlaybackChannel {
  static let channelName = "app.yubbly/player"
  private static let historyKey = "yubbly.history"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "state":
      result(Self.idleState)
    case "history":
      result(UserDefaults.standard.array(forKey: Self.historyKey) ?? [])
    case "clearHistory":
      UserDefaults.standard.removeObject(forKey: Self.historyKey)
      result(nil)
    case "initialLink":
      result(nil)
    // These calls are harmless no-ops until a desktop playback adapter exists.
    case "stop", "pause", "seek", "configure":
      result(nil)
    case "load", "play":
      result(
        FlutterError(
          code: "UNSUPPORTED_PLATFORM",
          message: "Odtwarzanie audio na macOS nie jest jeszcze zaimplementowane. "
            + "Ta wersja obsługuje odtwarzanie tylko na Androidzie.",
          details: nil
        )
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Mirrors the shape of `PlaybackService.snapshot()` so `AppState` can parse
  /// it without platform-specific branches.
  private static let idleState: [String: Any] = [
    "session": [String: Any](),
    "loaded": false,
    "positionMs": 0,
    "durationMs": 0,
    "playing": false,
    "buffering": false,
    "driftMs": 0,
    "error": "",
  ]
}

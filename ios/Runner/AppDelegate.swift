import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var playback: ApplePlaybackChannel?
  private var jsChallenge: AppleJsChallengeChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    playback = ApplePlaybackChannel(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    jsChallenge = AppleJsChallengeChannel(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}


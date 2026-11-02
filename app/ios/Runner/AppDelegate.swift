import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var intentChannel: FlutterMethodChannel?
  // The first activation is the cold launch; Flutter pulls the pending phrase
  // itself then (consumePendingReminder), so we must not also consume it here.
  private var didHandleColdStart = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Siri Shortcut bridge (CLAUDE.md Phase 5). The App Intent (SuryaIntents.swift)
    // stashes the spoken phrase; we hand it to Flutter over this channel.
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "surya/intents",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "consumePendingReminder":
          // Cold-start: Flutter pulls (and clears) any text that launched us.
          result(SuryaIntentStore.consume())
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      self.intentChannel = channel
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Warm-start: the app was already running when the intent fired. Push any
  // pending phrase to Flutter once we're active again.
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // Skip the first (cold-launch) activation — Flutter consumes the pending
    // phrase via consumePendingReminder during startup.
    guard didHandleColdStart else {
      didHandleColdStart = true
      return
    }
    if let text = SuryaIntentStore.consume() {
      intentChannel?.invokeMethod("prefillReminder", arguments: text)
    }
  }
}

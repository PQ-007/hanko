import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerAppIconChannel(engineBridge.pluginRegistry.registrar(forPlugin: "HankoAppIcon")!.messenger())
  }

  /// "hanko/app_icon": the home-screen icon follows the app theme
  /// (core/app_icon.dart). Цайвар is the primary AppIcon; Бараан and Цэнхэр
  /// are the alternate sets AppIconDark / AppIconBlue (compiled in via
  /// ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES). iOS itself shows a short
  /// "you have changed the icon" notice — that can't be suppressed.
  private func registerAppIconChannel(_ messenger: FlutterBinaryMessenger) {
    let names: [String: String?] = ["paper": nil, "dark": "AppIconDark", "blue": "AppIconBlue"]
    FlutterMethodChannel(name: "hanko/app_icon", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "set" else { return result(FlutterMethodNotImplemented) }
        guard let key = call.arguments as? String, let target = names[key] else {
          return result(FlutterError(code: "bad_icon", message: "unknown icon", details: nil))
        }
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != target else { return result(nil) }
        app.setAlternateIconName(target) { error in
          result(error.map { FlutterError(code: "icon_failed", message: $0.localizedDescription, details: nil) })
        }
      }
  }
}

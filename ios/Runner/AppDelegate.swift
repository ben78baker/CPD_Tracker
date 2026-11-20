import UIKit
import Flutter

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
    let channel = FlutterMethodChannel(
      name: "cpd_tracker/migration_storage",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "availableBytes" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String, !path.isEmpty else {
        result(FlutterError(code: "missing_path", message: "A destination path is required.", details: nil))
        return
      }
      guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
            let free = attributes[.systemFreeSize] as? NSNumber else {
        result(FlutterError(code: "storage_unavailable", message: "Could not measure destination capacity.", details: nil))
        return
      }
      result(free.int64Value)
    }
  }
}

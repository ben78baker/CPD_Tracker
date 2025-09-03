import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  lazy var flutterEngine = FlutterEngine(name: "cpd_engine")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Boot a dedicated FlutterEngine and register plugins against this engine
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    // Attach a FlutterViewController backed by the same engine
    self.window = UIWindow(frame: UIScreen.main.bounds)
    self.window?.rootViewController = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    self.window?.makeKeyAndVisible()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

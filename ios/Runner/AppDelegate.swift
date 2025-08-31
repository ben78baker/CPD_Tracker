import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {


  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // ensure a window exists and attach Flutter VC
    if self.window == nil {
      self.window = UIWindow(frame: UIScreen.main.bounds)
    }
    if self.window?.rootViewController == nil {
      let flutterVC = FlutterViewController(project: nil, nibName: nil, bundle: nil)
      self.window?.rootViewController = flutterVC
      self.window?.makeKeyAndVisible()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
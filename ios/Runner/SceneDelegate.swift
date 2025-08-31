import UIKit
import Flutter

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene,
             willConnectTo session: UISceneSession,
             options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }

    // Create a Flutter view controller and make it the root.
    let flutterVC = FlutterViewController(project: nil, nibName: nil, bundle: nil)

    let win = UIWindow(windowScene: windowScene)
    win.rootViewController = flutterVC
    win.makeKeyAndVisible()
    self.window = win
  }
}
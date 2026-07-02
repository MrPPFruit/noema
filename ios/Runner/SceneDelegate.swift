import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    enforcePortraitGeometry(scene)
  }

  private func enforcePortraitGeometry(_ scene: UIScene) {
    guard #available(iOS 16.0, *), let windowScene = scene as? UIWindowScene else {
      return
    }
    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
  }
}

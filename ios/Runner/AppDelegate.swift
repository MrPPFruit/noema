import Flutter
import Photos
import PhotosUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingPickerResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return .portrait
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerNoemaChannels(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerNoemaChannels(binaryMessenger messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(
      name: "noema/local_storage",
      binaryMessenger: messenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "getStorageDirectory":
        self.resolveStorageDirectory(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(
      name: "noema/external_links",
      binaryMessenger: messenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "openUrl":
        self.openExternalUrl(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(
      name: "noema/media_picker",
      binaryMessenger: messenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "galleryAccessStatus":
        self.galleryAccessStatus(result: result)
      case "requestGalleryAccess":
        self.requestGalleryAccess(result: result)
      case "pickImages":
        self.pickImages(call: call, result: result)
      case "loadMetadata":
        self.loadMetadata(call: call, result: result)
      case "createThumbnail":
        self.createImageFile(call: call, result: result, kind: "thumb")
      case "createPreview":
        self.createImageFile(call: call, result: result, kind: "preview")
      case "deleteMediaItems":
        self.deleteMediaItems(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func resolveStorageDirectory(result: FlutterResult) {
    do {
      result(try noemaStorageUrl().path)
    } catch {
      result(FlutterError(
        code: "storage_unavailable",
        message: "Noema storage directory is unavailable.",
        details: error.localizedDescription
      ))
    }
  }

  private func noemaStorageUrl() throws -> URL {
    let supportUrl = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let noemaUrl = supportUrl.appendingPathComponent("Noema", isDirectory: true)
    try FileManager.default.createDirectory(
      at: noemaUrl,
      withIntermediateDirectories: true
    )
    return noemaUrl
  }

  private func galleryAccessStatus(result: FlutterResult) {
    if #available(iOS 14.0, *) {
      result(galleryAccessValue(PHPhotoLibrary.authorizationStatus(for: .readWrite)))
    } else {
      result(galleryAccessValue(PHPhotoLibrary.authorizationStatus()))
    }
  }

  private func requestGalleryAccess(result: @escaping FlutterResult) {
    if #available(iOS 14.0, *) {
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
        DispatchQueue.main.async {
          result(self.galleryAccessValue(status))
        }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { status in
        DispatchQueue.main.async {
          result(self.galleryAccessValue(status))
        }
      }
    }
  }

  private func galleryAccessValue(_ status: PHAuthorizationStatus) -> String {
    if #available(iOS 14.0, *), status == .limited {
      return "partial"
    }
    switch status {
    case .authorized:
      return "full"
    case .denied, .restricted:
      return "denied"
    case .notDetermined:
      return "denied"
    default:
      return "unavailable"
    }
  }

  private func pickImages(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 14.0, *) else {
      result(FlutterError(
        code: "photo_picker_unavailable",
        message: "Noema iOS photo picker requires iOS 14 or later.",
        details: nil
      ))
      return
    }

    guard pendingPickerResult == nil else {
      result(FlutterError(
        code: "photo_picker_active",
        message: "Noema photo picker is already active.",
        details: nil
      ))
      return
    }

    guard let presenter = topViewController() else {
      result(FlutterError(
        code: "presentation_unavailable",
        message: "Noema could not present the photo picker.",
        details: nil
      ))
      return
    }

    let arguments = call.arguments as? [String: Any]
    let limit = positiveInt(arguments?["limit"], fallback: 300)
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = limit > 0 ? limit : 0

    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    pendingPickerResult = result
    presenter.present(picker, animated: true)
  }

  private func loadMetadata(call: FlutterMethodCall, result: FlutterResult) {
    guard
      let asset = assetFromCall(call)
    else {
      result(nil)
      return
    }
    result(mediaMap(for: asset))
  }

  private func createImageFile(
    call: FlutterMethodCall,
    result: @escaping FlutterResult,
    kind: String
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let uri = arguments["uri"] as? String,
      !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let asset = asset(with: uri)
    else {
      result(nil)
      return
    }

    let maxSize = positiveInt(arguments["maxSize"], fallback: kind == "preview" ? 1800 : 320)
    let outputUrl: URL
    do {
      outputUrl = try mediaCacheUrl(uri: uri, kind: kind, maxSize: maxSize)
      if FileManager.default.fileExists(atPath: outputUrl.path) {
        result(outputUrl.path)
        return
      }
    } catch {
      result(FlutterError(
        code: "cache_unavailable",
        message: "Noema could not prepare the iOS media cache.",
        details: error.localizedDescription
      ))
      return
    }

    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .fast

    let targetSize = CGSize(width: maxSize, height: maxSize)
    var completed = false
    PHImageManager.default().requestImage(
      for: asset,
      targetSize: targetSize,
      contentMode: .aspectFit,
      options: options
    ) { image, info in
      let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
      if degraded || completed {
        return
      }
      completed = true

      guard
        let image,
        let data = image.jpegData(compressionQuality: kind == "preview" ? 0.9 : 0.82)
      else {
        DispatchQueue.main.async {
          result(nil)
        }
        return
      }

      do {
        try data.write(to: outputUrl, options: .atomic)
        DispatchQueue.main.async {
          result(outputUrl.path)
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "cache_write_failed",
            message: "Noema could not write the iOS media cache file.",
            details: error.localizedDescription
          ))
        }
      }
    }
  }

  private func deleteMediaItems(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let uris = arguments["uris"] as? [String]
    else {
      result(false)
      return
    }

    let identifiers = uris
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !identifiers.isEmpty else {
      result(false)
      return
    }

    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
    guard fetchResult.count == identifiers.count else {
      result(false)
      return
    }

    PHPhotoLibrary.shared().performChanges({
      PHAssetChangeRequest.deleteAssets(fetchResult)
    }) { success, error in
      DispatchQueue.main.async {
        if success {
          result(["deleted": true, "count": fetchResult.count])
        } else if let error {
          result(FlutterError(
            code: "delete_failed",
            message: "Noema could not delete the iOS Photos assets.",
            details: error.localizedDescription
          ))
        } else {
          result(false)
        }
      }
    }
  }

  private func assetFromCall(_ call: FlutterMethodCall) -> PHAsset? {
    guard
      let arguments = call.arguments as? [String: Any],
      let uri = arguments["uri"] as? String
    else {
      return nil
    }
    return asset(with: uri)
  }

  private func asset(with localIdentifier: String) -> PHAsset? {
    let identifier = localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !identifier.isEmpty else {
      return nil
    }
    let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
    return result.firstObject
  }

  private func mediaMap(for asset: PHAsset) -> [String: Any] {
    var map: [String: Any] = [
      "uri": asset.localIdentifier,
      "id": asset.localIdentifier,
      "name": originalFilename(for: asset),
      "width": asset.pixelWidth,
      "height": asset.pixelHeight
    ]
    if let creationDate = asset.creationDate {
      map["takenAtMillis"] = millis(from: creationDate)
    }
    if let modificationDate = asset.modificationDate {
      map["modifiedAtMillis"] = millis(from: modificationDate)
    }
    return map
  }

  private func originalFilename(for asset: PHAsset) -> String {
    return PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "photo"
  }

  private func millis(from date: Date) -> Int {
    return Int(date.timeIntervalSince1970 * 1000)
  }

  private func mediaCacheUrl(uri: String, kind: String, maxSize: Int) throws -> URL {
    let directory = try noemaStorageUrl()
      .appendingPathComponent("noema_media", isDirectory: true)
      .appendingPathComponent(kind == "preview" ? "previews" : "thumbs", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let fileName = "v5_\(javaStringHashAbs(uri))_\(kind)_\(maxSize).jpg"
    return directory.appendingPathComponent(fileName, isDirectory: false)
  }

  private func javaStringHashAbs(_ value: String) -> String {
    var hash: Int32 = 0
    for codeUnit in value.utf16 {
      hash = hash &* 31 &+ Int32(bitPattern: UInt32(codeUnit))
    }
    if hash == Int32.min {
      return String(hash)
    }
    return String(abs(hash))
  }

  private func positiveInt(_ value: Any?, fallback: Int) -> Int {
    if let value = value as? Int, value > 0 {
      return value
    }
    if let value = value as? NSNumber, value.intValue > 0 {
      return value.intValue
    }
    if let value = value as? String, let parsed = Int(value), parsed > 0 {
      return parsed
    }
    return fallback
  }

  private func topViewController() -> UIViewController? {
    let windowScenes = UIApplication.shared.connectedScenes.compactMap {
      $0 as? UIWindowScene
    }
    let root = windowScenes
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController ?? window?.rootViewController
    return topPresentedViewController(from: root)
  }

  private func topPresentedViewController(from root: UIViewController?) -> UIViewController? {
    if let navigation = root as? UINavigationController {
      return topPresentedViewController(from: navigation.visibleViewController)
    }
    if let tab = root as? UITabBarController {
      return topPresentedViewController(from: tab.selectedViewController)
    }
    if let presented = root?.presentedViewController {
      return topPresentedViewController(from: presented)
    }
    return root
  }

  private func openExternalUrl(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let source = arguments["url"] as? String,
      let url = URL(string: source),
      let scheme = url.scheme?.lowercased()
    else {
      result(FlutterError(
        code: "invalid_url",
        message: "Noema external link URL is invalid.",
        details: nil
      ))
      return
    }

    guard scheme == "http" || scheme == "https" else {
      result(FlutterError(
        code: "unsupported_url_scheme",
        message: "Noema external links only support http and https.",
        details: scheme
      ))
      return
    }

    UIApplication.shared.open(url, options: [:]) { success in
      if success {
        result(nil)
      } else {
        result(FlutterError(
          code: "open_failed",
          message: "Noema could not open the external link.",
          details: source
        ))
      }
    }
  }
}

@available(iOS 14.0, *)
extension AppDelegate: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)

    let flutterResult = pendingPickerResult
    pendingPickerResult = nil

    let identifiers = results.compactMap { result in
      result.assetIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }

    guard !identifiers.isEmpty else {
      flutterResult?([])
      return
    }

    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
    var assetsById: [String: PHAsset] = [:]
    fetchResult.enumerateObjects { asset, _, _ in
      assetsById[asset.localIdentifier] = asset
    }

    let maps = identifiers.compactMap { identifier -> [String: Any]? in
      guard let asset = assetsById[identifier] else {
        return nil
      }
      return mediaMap(for: asset)
    }
    flutterResult?(maps)
  }
}

@objc(PortraitFlutterViewController)
class PortraitFlutterViewController: FlutterViewController {
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    return .portrait
  }

  override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
    return .portrait
  }

  override var shouldAutorotate: Bool {
    return false
  }
}

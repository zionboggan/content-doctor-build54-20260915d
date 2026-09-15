import Flutter
import UIKit
import Security

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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrialCredentials") else { return }
    let channel = FlutterMethodChannel(name: "trial_reels/credentials", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: String],
            let origin = args["origin"], origin.hasPrefix("https://") else {
        result(FlutterError(code: "invalid_origin", message: "HTTPS origin required", details: nil))
        return
      }
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "trial_reels.gateway",
        kSecAttrAccount as String: origin
      ]
      if call.method == "read" {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { result(nil); return }
        guard status == errSecSuccess, let data = item as? Data else {
          result(FlutterError(code: "keychain_read", message: "Could not read device key", details: nil)); return
        }
        result(String(data: data, encoding: .utf8))
      } else if call.method == "write", let token = args["token"], !token.isEmpty {
        let data = Data(token.utf8)
        var entry = query
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        var status = SecItemAdd(entry as CFDictionary, nil)
        if status == errSecDuplicateItem {
          status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        result(status == errSecSuccess ? nil : FlutterError(code: "keychain_write", message: "Could not save device key", details: nil))
      } else if call.method == "delete" {
        let status = SecItemDelete(query as CFDictionary)
        result(status == errSecSuccess || status == errSecItemNotFound ? nil : FlutterError(code: "keychain_delete", message: "Could not clear device key", details: nil))
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

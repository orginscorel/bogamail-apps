import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Bildirime dokunarak soğuk açılışı yakalamak için temsilci en başta atanır.
    UNUserNotificationCenter.current().delegate = BogaPush.shared
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let r = engineBridge.pluginRegistry.registrar(forPlugin: "BogaPush") {
      BogaPush.register(with: r)
    }
  }
}

/// Apple anlık bildirimleri: izin, cihaz anahtarı, dokunulan bildirim, rozet. Dart tarafı: boga_ortak/lib/src/push.dart
final class BogaPush: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
  static let shared = BogaPush()
  private var channel: FlutterMethodChannel?
  private var bekleyen: [FlutterResult] = []
  private var token: String?
  private var acilis: [String: Any]?

  static func register(with registrar: FlutterPluginRegistrar) {
    let ch = FlutterMethodChannel(name: "boga/push", binaryMessenger: registrar.messenger())
    shared.channel = ch
    registrar.addMethodCallDelegate(shared, channel: ch)
    registrar.addApplicationDelegate(shared)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "kaydol":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { izin, _ in
        DispatchQueue.main.async {
          guard izin else { result(nil); return }
          if let t = self.token { result(t); return }
          self.bekleyen.append(result)
          UIApplication.shared.registerForRemoteNotifications()
          DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.bitir(nil) }
        }
      }
    case "izin":
      // Bildirim izin durumu: verildi | reddedildi | sorulmadi (Dart: lib/veri/bildirim.dart).
      UNUserNotificationCenter.current().getNotificationSettings { s in
        let v: String
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral: v = "verildi"
        case .denied: v = "reddedildi"
        default: v = "sorulmadi"
        }
        DispatchQueue.main.async { result(v) }
      }
    case "baslangic":
      result(acilis)
      acilis = nil
    case "rozet":
      let n = (call.arguments as? Int) ?? 0
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(n) { _ in }
      } else {
        UIApplication.shared.applicationIconBadgeNumber = n
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func bitir(_ t: String?) {
    let l = bekleyen
    bekleyen = []
    l.forEach { $0(t) }
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    token = deviceToken.map { String(format: "%02x", $0) }.joined()
    bitir(token)
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    bitir(nil)
  }

  private func temiz(_ u: [AnyHashable: Any]) -> [String: Any] {
    var o = [String: Any]()
    for (k, v) in u {
      guard let k = k as? String, k != "aps" else { continue }
      if v is String || v is NSNumber { o[k] = v }
    }
    return o
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    channel?.invokeMethod("geldi", arguments: temiz(notification.request.content.userInfo))
    completionHandler([.banner, .list, .sound, .badge])
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    let v = temiz(response.notification.request.content.userInfo)
    acilis = v
    channel?.invokeMethod("acildi", arguments: v)
    completionHandler()
  }
}

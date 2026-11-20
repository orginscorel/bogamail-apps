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
    // Eklentiler (flutter_local_notifications vb.) temsilciyi değiştirmiş olabilir: APNs dokunma/öndeyken gösterme
    // BogaPush'ta kalsın.
    UNUserNotificationCenter.current().delegate = BogaPush.shared
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
      // Bildirim izin durumu: verildi | reddedildi | sorulmadi (Dart: lib/veri/bildirim_izni.dart).
      UNUserNotificationCenter.current().getNotificationSettings { s in
        let v: String
        switch s.authorizationStatus {
        case .authorized, .provisional: v = "verildi"
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

  /// Öndeyken: Dart'a o oda/ileti açık mı diye sorulur (300 ms içinde yanıt yoksa gösterilir). Açıksa yalnız
  /// bildirim merkezine düşer, banner/ses yok.
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    let bilgi = temiz(notification.request.content.userInfo)
    channel?.invokeMethod("geldi", arguments: bilgi)
    guard let ch = channel else {
      completionHandler([.banner, .list, .sound, .badge])
      return
    }
    var bitti = false
    let bitir: (Bool) -> Void = { goster in
      if bitti { return }
      bitti = true
      completionHandler(goster ? [.banner, .list, .sound, .badge] : [.list, .badge])
    }
    ch.invokeMethod("gosterilsinMi", arguments: bilgi) { r in
      DispatchQueue.main.async { bitir((r as? Bool) ?? true) }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { bitir(true) }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    let v = temiz(response.notification.request.content.userInfo)
    acilis = v
    channel?.invokeMethod("acildi", arguments: v)
    completionHandler()
  }
}

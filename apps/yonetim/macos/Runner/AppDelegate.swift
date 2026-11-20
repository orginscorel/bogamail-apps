import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = BogaPush.shared
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    BogaPush.shared.kayitli(deviceToken)
  }

  override func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    BogaPush.shared.kayitHatasi()
  }
}

/// Apple anlık bildirimleri (Mac): izin, cihaz anahtarı, dokunulan bildirim, Dock rozeti.
final class BogaPush: NSObject, UNUserNotificationCenterDelegate {
  static let shared = BogaPush()
  private var channel: FlutterMethodChannel?
  private var bekleyen: [FlutterResult] = []
  private var token: String?
  private var acilis: [String: Any]?

  func bagla(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "boga/push", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    channel = ch
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "kaydol":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { izin, _ in
        DispatchQueue.main.async {
          guard izin else { result(nil); return }
          if let t = self.token { result(t); return }
          self.bekleyen.append(result)
          NSApplication.shared.registerForRemoteNotifications()
          DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.bitir(nil) }
        }
      }
    case "baslangic":
      result(acilis)
      acilis = nil
    case "rozet":
      let n = (call.arguments as? Int) ?? 0
      NSApplication.shared.dockTile.badgeLabel = n > 0 ? String(n) : nil
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

  func kayitli(_ deviceToken: Data) {
    token = deviceToken.map { String(format: "%02x", $0) }.joined()
    bitir(token)
  }

  func kayitHatasi() { bitir(nil) }

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
    NSApplication.shared.activate(ignoringOtherApps: true)
    completionHandler()
  }
}

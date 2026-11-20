import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: max(windowFrame.width, 1180), height: max(windowFrame.height, 780))
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    BogaPush.shared.bagla(flutterViewController.engine.binaryMessenger)
    BogaArkaplan.bagla(flutterViewController.engine.binaryMessenger)
    // flutter_local_notifications eklentisi kaydolurken bildirim merkezinin temsilcisini kendine alır; APNs
    // bildirimine dokunma / öndeyken gösterme BogaPush'ta kalsın diye temsilci geri atanır.
    UNUserNotificationCenter.current().delegate = BogaPush.shared

    super.awakeFromNib()
    // Kapat düğmesi pencereyi yok etmez, gizler (uygulama arka planda çalışır; Dock'tan yeniden açılır).
    self.isReleasedWhenClosed = false
  }
}

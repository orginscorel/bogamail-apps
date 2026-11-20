import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: max(windowFrame.width, 1180), height: max(windowFrame.height, 780))
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    BogaPush.shared.bagla(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let defaultContentSize = NSSize(width: 960, height: 720)
    let minimumContentSize = NSSize(width: 800, height: 600)

    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    minSize = minimumContentSize
    contentMinSize = minimumContentSize

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(defaultContentSize)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

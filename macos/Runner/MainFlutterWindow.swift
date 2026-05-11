import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let defaultContentSize = NSSize(width: 1120, height: 708)

    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    minSize = defaultContentSize
    contentMinSize = defaultContentSize

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(defaultContentSize)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

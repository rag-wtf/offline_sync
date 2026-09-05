import Cocoa
import FlutterMacOS
import Foundation

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "offline_sync/storage",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup",
            let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard !path.isEmpty else {
        result(FlutterError(code: "BACKUP_EXCLUSION_FAILED", message: "Path is empty", details: nil))
        return
      }
      let url = URL(fileURLWithPath: path)
      do {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "BACKUP_EXCLUSION_FAILED", message: error.localizedDescription, details: path))
      }
    }

    super.awakeFromNib()
  }
}

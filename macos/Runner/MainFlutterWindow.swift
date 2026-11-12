import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMethodChannel(
      name: "dev.jeeth.daybreak/actions",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "timeZone":
        result(TimeZone.current.identifier)
      case "openLink":
        guard let arguments = call.arguments as? [String: String],
              let value = arguments["url"], let url = URL(string: value),
              url.scheme == "https" else {
          result(FlutterError(code: "invalid_url", message: nil, details: nil))
          return
        }
        result(NSWorkspace.shared.open(url) ? nil :
          FlutterError(code: "could_not_open_url", message: nil, details: nil))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(
        name: "dev.jeeth.daybreak/actions", binaryMessenger: controller.binaryMessenger
      ).setMethodCallHandler { call, result in
        switch call.method {
        case "timeZone":
          result(TimeZone.current.identifier)
        case "openLink":
          guard let args = call.arguments as? [String: String],
                let text = args["url"], let url = URL(string: text), url.scheme == "https" else {
            result(FlutterError(code: "invalid_url", message: nil, details: nil))
            return
          }
          application.open(url) { opened in
            result(opened ? nil : FlutterError(code: "could_not_open_url", message: nil, details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

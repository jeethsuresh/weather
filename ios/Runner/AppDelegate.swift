import Flutter
import UIKit
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "dev.jeeth.daybreak.hourly", frequency: NSNumber(value: 60 * 60)
    )
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

  override func application(
    _ application: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "daybreak" && url.host == "weather" {
      return true
    }
    return super.application(application, open: url, options: options)
  }
}

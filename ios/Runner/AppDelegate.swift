import Flutter
import UIKit
import SafariServices
import WebKit

@UIApplicationMain
class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController
        let browserChannel = FlutterMethodChannel(
            name: "io.supabase.myareaapp/browser",
            binaryMessenger: controller.binaryMessenger)
        
        browserChannel.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "closeInAppBrowser":
                // Find and dismiss any presented view controllers
                if let presentedVC = UIApplication.shared.windows.first?.rootViewController?.presentedViewController {
                    presentedVC.dismiss(animated: false) {
                        print("Browser dismissed successfully")
                        result(nil)
                    }
                } else {
                    print("No browser view controller found to dismiss")
                    result(nil)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
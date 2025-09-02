import Flutter
import UIKit
import SafariServices
import WebKit

class BrowserViewController: NSObject {
    static let shared = BrowserViewController()
    weak var currentWebView: WKWebView?
    weak var currentViewController: UIViewController?
    
    func closeInAppBrowser() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // First try to close the web view
            if let webView = self.currentWebView {
                // Stop any ongoing requests and clear data
                webView.stopLoading()
                WKWebsiteDataStore.default().removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                    modifiedSince: Date(timeIntervalSince1970: 0)
                ) { }
                
                // Try to close via JavaScript
                webView.evaluateJavaScript("""
                    window.close();
                    window.location.href = 'about:blank';
                    history.pushState(null, '', 'about:blank');
                    document.write('');
                    document.close();
                """, completionHandler: nil)
                
                // Force remove the web view
                webView.removeFromSuperview()
                webView.configuration.userContentController.removeAllUserScripts()
                self.currentWebView = nil
            }
            
            // Then try to dismiss the view controller immediately
            if let viewController = self.currentViewController {
                // Force immediate dismissal of all presented view controllers
                var currentVC = viewController
                while let presentedVC = currentVC.presentedViewController {
                    presentedVC.dismiss(animated: false, completion: nil)
                    currentVC = presentedVC
                }
                
                // Dismiss the main view controller
                viewController.dismiss(animated: false) {
                    self.currentViewController = nil
                }
            }
            
            // Post a notification that can be observed by Flutter
            NotificationCenter.default.post(name: NSNotification.Name("BrowserClosed"), object: nil)
            
            // Clear any remaining resources
            self.currentWebView = nil
            self.currentViewController = nil
            
            // Force update UI on next run loop
            DispatchQueue.main.async {
                // Force layout update
                UIApplication.shared.windows.forEach { window in
                    window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
                    window.setNeedsLayout()
                    window.layoutIfNeeded()
                }
            }
        }
    }
    
    func setCurrentWebView(_ webView: WKWebView) {
        self.currentWebView = webView
    }
    
    func setCurrentViewController(_ viewController: UIViewController) {
        self.currentViewController = viewController
    }
}
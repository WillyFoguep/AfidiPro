import UIKit
import UserNotifications
import WebKit
import Capacitor
#if canImport(FirebaseMessaging)
import FirebaseCore
import FirebaseMessaging
#endif

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if canImport(FirebaseMessaging)
        // Nécessite GoogleService-Info.plist dans la cible App (voir MOBILE_PUSH.md / guide iOS)
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        #endif

        // Demande la permission de notifications dès le premier lancement.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url. Feel free to add additional processing here,
        // but if you want the App API to support tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        // Le serveur envoie via FCM : on transmet au plugin le jeton FCM, pas le jeton APNs brut.
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, error in
            if let error = error {
                NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
            } else if let token = token {
                NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: token)
            }
        }
        #else
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }

}

// MARK: - WebView : pont push et liens externes

// Le site distant (server.url) est chargé dans la WebView : ce script est injecté à chaque page.
// Le jeton est confié à window.afidiPush ; le site fait la requête authentifiée (voir MOBILE_PUSH.md).
private let nativePushScript = #"""
(function () {
  var cap = window.Capacitor;
  if (!cap || !cap.isNativePlatform || !cap.isNativePlatform()) return;
  if (window.__afidiNativePushLoaded) return;
  window.__afidiNativePushLoaded = true;

  var Push = cap.Plugins.PushNotifications;
  var Prefs = cap.Plugins.Preferences;
  var DEVICE_ID_KEY = "afidipro_device_id";

  function uuidV4() {
    var b = new Uint8Array(16);
    crypto.getRandomValues(b);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    var h = Array.prototype.map.call(b, function (x) { return ("0" + x.toString(16)).slice(-2); }).join("");
    return h.slice(0, 8) + "-" + h.slice(8, 12) + "-" + h.slice(12, 16) + "-" + h.slice(16, 20) + "-" + h.slice(20);
  }

  function getDeviceId() {
    return Prefs.get({ key: DEVICE_ID_KEY }).then(function (r) {
      if (r.value && r.value.length >= 32) return r.value;
      var id = uuidV4();
      return Prefs.set({ key: DEVICE_ID_KEY, value: id }).then(function () { return id; });
    });
  }

  function waitForBridge(tries) {
    return new Promise(function (resolve) {
      (function check(n) {
        if (window.afidiPush && window.afidiPush.register) return resolve(window.afidiPush);
        if (n <= 0) return resolve(null);
        setTimeout(function () { check(n - 1); }, 250);
      })(tries);
    });
  }

  function registerWithSite(token) {
    return Promise.all([getDeviceId(), waitForBridge(40)]).then(function (res) {
      if (!res[1]) return console.warn("[push] window.afidiPush introuvable");
      return res[1].register(token, cap.getPlatform(), res[0]);
    });
  }

  // Lien de notification : chemin relatif uniquement, jamais une autre origine.
  function openLink(link) {
    if (typeof link !== "string") return;
    if (link.charAt(0) !== "/" || link.charAt(1) === "/" || link.indexOf("\\") !== -1) return;
    window.location.href = window.location.origin + link;
  }

  Push.removeAllListeners()
    .catch(function () {})
    .then(function () {
      Push.addListener("registration", function (t) {
        registerWithSite(t.value).catch(function (e) { console.error("[push] register", e); });
      });
      Push.addListener("registrationError", function (e) {
        console.error("[push] registrationError", JSON.stringify(e));
      });
      Push.addListener("pushNotificationActionPerformed", function (action) {
        var data = action && action.notification && action.notification.data;
        openLink(data && data.link);
      });
      // La permission est demandée au lancement par AppDelegate.
      return Push.register();
    })
    .catch(function (e) { console.error("[push] init", e); });
})();
"""#

enum ExternalLinks {
    // Domaines à ouvrir dans l'application correspondante (WhatsApp, Facebook, Messenger).
    private static func matches(_ host: String, _ domain: String) -> Bool {
        return host == domain || host.hasSuffix("." + domain)
    }

    static func shouldOpenInApp(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return false }
        return host == "wa.me" || matches(host, "whatsapp.com")
            || matches(host, "facebook.com") || host == "fb.me" || host == "fb.com" || host == "m.me"
    }

    // Lien universel : ouvre l'app si elle est installée, sinon Safari.
    static func open(_ url: URL) {
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
            if !opened {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
}

// Intercepte la navigation, laisse tout le reste au gestionnaire de Capacitor.
final class NavigationProxy: NSObject, WKNavigationDelegate {
    private let original: WKNavigationDelegate

    init(original: WKNavigationDelegate) {
        self.original = original
    }

    override func responds(to aSelector: Selector!) -> Bool {
        return super.responds(to: aSelector) || original.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return original
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, ExternalLinks.shouldOpenInApp(url) {
            ExternalLinks.open(url)
            decisionHandler(.cancel)
            return
        }
        // Capacitor (WebViewDelegationHandler) implémente cette méthode.
        original.webView?(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
    }
}

// Référencé par Main.storyboard (à la place de CAPBridgeViewController).
class MainViewController: CAPBridgeViewController {
    private var navigationProxy: NavigationProxy?

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        guard let webView = webView else { return }

        let script = WKUserScript(source: nativePushScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)

        if let original = webView.navigationDelegate {
            let proxy = NavigationProxy(original: original)
            navigationProxy = proxy
            webView.navigationDelegate = proxy
        }
    }
}

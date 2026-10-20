// Injecté par MainActivity à chaque fin de chargement de page (site distant).
// Contrat : voir MOBILE_PUSH.md. Le natif n'appelle jamais l'API lui-même :
// il passe le jeton à window.afidiPush, le site fait la requête authentifiée.
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
    var h = Array.prototype.map
      .call(b, function (x) {
        return ("0" + x.toString(16)).slice(-2);
      })
      .join("");
    return (
      h.slice(0, 8) + "-" + h.slice(8, 12) + "-" + h.slice(12, 16) + "-" +
      h.slice(16, 20) + "-" + h.slice(20)
    );
  }

  function getDeviceId() {
    return Prefs.get({ key: DEVICE_ID_KEY }).then(function (r) {
      if (r.value && r.value.length >= 32) return r.value;
      var id = uuidV4();
      return Prefs.set({ key: DEVICE_ID_KEY, value: id }).then(function () {
        return id;
      });
    });
  }

  // window.afidiPush est défini dans le <head> du site avant l'hydratation.
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

  // La permission (Android 13+), le canal et l'ouverture du lien au tap sont gérés
  // par MainActivity. Le jeton FCM s'obtient sans la permission : on l'enregistre toujours.
  Push.removeAllListeners()
    .catch(function () {})
    .then(function () {
      Push.addListener("registration", function (t) {
        registerWithSite(t.value).catch(function (e) {
          console.error("[push] register", e);
        });
      });
      Push.addListener("registrationError", function (e) {
        console.error("[push] registrationError", JSON.stringify(e));
      });
      return Push.register();
    })
    .catch(function (e) {
      console.error("[push] init", e);
    });
})();

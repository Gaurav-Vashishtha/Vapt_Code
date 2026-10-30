var eventName =
  typeof Turbolinks !== "undefined" ? "turbolinks:load" : "DOMContentLoaded";

if (!document.documentElement.hasAttribute("data-turbolinks-preview")) {
  document.addEventListener(eventName, function flash() {
    var el = document.getElementById("shopify-app-flash");
    if (!el || !el.dataset || el.dataset.flash == null) return;

    var flashData;
    try {
      flashData = JSON.parse(el.dataset.flash);
    } catch (_e) {
      return;
    }

    function showWithShopifyToast(message, isError) {
      var toast = window.shopify && window.shopify.toast;
      if (!toast || typeof toast.show !== "function") return false;
      var opts = { duration: 5000 };
      if (isError) opts.isError = true;
      toast.show(message, opts);
      return true;
    }

    var bridge = window["app-bridge"];
    var Toast = bridge && bridge.actions && bridge.actions.Toast;
    var legacyApp = typeof window !== "undefined" ? window.app : undefined;

    if (flashData.notice) {
      if (!showWithShopifyToast(flashData.notice, false) && Toast && legacyApp) {
        Toast.create(legacyApp, {
          message: flashData.notice,
          duration: 5000,
        }).dispatch(Toast.Action.SHOW);
      }
    }

    if (flashData.error) {
      if (!showWithShopifyToast(flashData.error, true) && Toast && legacyApp) {
        Toast.create(legacyApp, {
          message: flashData.error,
          duration: 5000,
          isError: true,
        }).dispatch(Toast.Action.SHOW);
      }
    }
  });
}

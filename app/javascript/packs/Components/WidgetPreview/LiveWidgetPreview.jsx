import React, {
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { decamelizeKeys } from "humps";
import { StoreContext } from "../../Context/Store";
import { normalizeUiCustomization } from "../uiCustomizationCatalog";
import I18n from "../../i18n-lang";

const HOST_PATH = "/script/widget_preview";
const CHANNEL_OUT = "codk-preview";
const CHANNEL_IN = "codk-preview-host";

// Enough to coalesce a burst of keystrokes into one update, short enough that
// it still reads as live.
const SETTINGS_DEBOUNCE_MS = 120;

// The widget's own mobile breakpoint is 641px; this is the phone it lays out
// for, scaled to whatever width the preview pane gives us.
const FRAME = { width: 390, height: 740 };

// Space between the heading block and the frame.
const HEAD_GAP = 10;

/** The rail's section names, mapped onto the widget's own screens. */
const SCREEN_BY_SECTION = {
  phone: "phone",
  otp: "otp",
  address: "address",
  payment: "payment",
  // Not screens of their own: the host lands on the screen that carries them
  // and then opens the coupon card or the exit confirmation.
  coupons: "coupons",
  dialogs: "dialogs",
  "address-form": "address-form",
  processing: "processing",
  confirmed: "confirmed",
  // The widget has no "done" screen — the thank-you flow is an overlay on
  // top of payment, so that is the closest thing the rail can jump to.
  done: "payment",
};

/**
 * The real storefront widget, running in the admin.
 *
 * Rather than re-implementing the widget in React, this boots
 * notifik-svelte-app itself inside a host page that impersonates a storefront:
 * /script/widget_preview supplies the Shopify globals, a demo cart and a
 * deny-by-default network layer. What the merchant sees is the code their
 * customers get.
 *
 * Settings are pushed in as the snake_case payload the storefront receives, so
 * the widget's own mapper reads them exactly as it does in production, and
 * applied to the running widget rather than reloading it — an edit changes the
 * copy under the merchant's cursor without the preview blinking or losing the
 * screen they are on.
 */
const LiveWidgetPreview = ({ setting: settingProp, screen }) => {
  const ctx = useContext(StoreContext);
  const setting = settingProp || ctx?.setting?.[0] || {};
  const shop = ctx?.shop?.[0] || {};
  const domain = shop?.shopify_domain || "";

  const frameRef = useRef(null);
  const boxRef = useRef(null);
  const rootRef = useRef(null);
  const headRef = useRef(null);
  const hostReadyRef = useRef(false);
  const lastPayloadRef = useRef(null);

  const [base, setBase] = useState(null);
  const [available, setAvailable] = useState({ width: 0, height: 0 });

  // The saved settings, in the exact shape the storefront is served. Using the
  // server's payload as the base keeps the preview honest about which keys the
  // widget actually receives, and keeps everything else on the Setting record
  // (tokens, provider credentials) out of the preview altogether.
  useEffect(() => {
    if (!domain) return undefined;
    let cancelled = false;
    fetch(`/script/lightweight_settings?domain=${encodeURIComponent(domain)}`, {
      headers: { Accept: "application/json" },
    })
      .then((res) => (res.ok ? res.json() : {}))
      .then((json) => {
        if (!cancelled) setBase(json && typeof json === "object" ? json : {});
      })
      .catch(() => {
        if (!cancelled) setBase({});
      });
    return () => {
      cancelled = true;
    };
  }, [domain]);

  // The preview pane is both narrower and shorter than a phone, so the frame
  // keeps its real viewport size and is scaled to fit whichever axis runs out
  // first. The widget still lays out for the device it stands in for, and the
  // whole phone stays on screen instead of running off the bottom of the pane.
  useEffect(() => {
    const node = boxRef.current;
    if (!node) return undefined;

    const measure = () => {
      const pane = rootRef.current?.parentElement;
      const headHeight = headRef.current?.offsetHeight || 0;
      const paneStyle = pane ? window.getComputedStyle(pane) : null;
      const vertPadding = paneStyle
        ? parseFloat(paneStyle.paddingTop) + parseFloat(paneStyle.paddingBottom)
        : 0;
      const paneHeight = pane ? pane.clientHeight - vertPadding : 0;
      setAvailable({
        width: node.clientWidth,
        height: Math.max(0, paneHeight - headHeight - HEAD_GAP),
      });
    };

    measure();
    if (typeof ResizeObserver === "undefined") {
      window.addEventListener("resize", measure);
      return () => window.removeEventListener("resize", measure);
    }
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    if (rootRef.current?.parentElement) {
      observer.observe(rootRef.current.parentElement);
    }
    return () => observer.disconnect();
  }, []);

  // Overlay the unsaved draft on top. Only keys the storefront payload already
  // carries are copied over, so the editor can never widen what ships.
  const settings = useMemo(() => {
    if (!base) return null;
    const draft = decamelizeKeys(setting || {});
    const merged = { ...base };
    Object.keys(base).forEach((key) => {
      if (key in draft) merged[key] = draft[key];
    });
    // humps camelizes nested JSON keys on the way in and cannot reliably undo
    // it, so the two blobs with meaningful inner keys are rebuilt by hand.
    merged.ui_customization = normalizeUiCustomization(setting?.uiCustomization);
    merged.cod_form_config = setting?.codFormConfig || {};
    merged.active_discounts =
      setting?.activeDiscounts ?? base.active_discounts ?? [];
    return merged;
  }, [base, setting]);

  const post = useCallback((type, payload) => {
    const win = frameRef.current?.contentWindow;
    if (!win) return;
    try {
      win.postMessage(
        { source: CHANNEL_OUT, type, payload },
        window.location.origin
      );
    } catch (_e) {
      /* the host is same-origin; a failure here means it is simply not up yet */
    }
  }, []);

  const sendSettings = useCallback(
    (type) => {
      if (!settings) return;
      post(type, {
        shop: domain || "preview.myshopify.com",
        country: shop?.country_code || "IN",
        currency: shop?.currency || "INR",
        settings,
        screen: SCREEN_BY_SECTION[screen] || null,
      });
    },
    [post, settings, domain, shop?.country_code, shop?.currency, screen]
  );

  useEffect(() => {
    const onMessage = (event) => {
      // The host page (/script/widget_preview) is served from this origin, so
      // anything arriving from elsewhere is not our preview frame.
      if (event.origin !== window.location.origin) return;
      if (event.source !== frameRef.current?.contentWindow) return;
      const data = event.data;
      if (!data || data.source !== CHANNEL_IN) return;
      if (data.type === "ready") {
        hostReadyRef.current = true;
        lastPayloadRef.current = JSON.stringify(settings);
        sendSettings("init");
      }
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [sendSettings, settings]);

  // An edit is applied to the running widget, so this costs nothing visible —
  // the debounce is only here to coalesce keystrokes.
  useEffect(() => {
    if (!hostReadyRef.current || !settings) return undefined;
    const next = JSON.stringify(settings);
    if (next === lastPayloadRef.current) return undefined;
    const timer = setTimeout(() => {
      lastPayloadRef.current = next;
      sendSettings("settings");
    }, SETTINGS_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [settings, sendSettings]);

  // Changing section only jumps the widget to that screen.
  useEffect(() => {
    if (!hostReadyRef.current) return;
    post("screen", { screen: SCREEN_BY_SECTION[screen] || "phone" });
  }, [screen, post]);

  const scale = Math.min(
    1,
    available.width > 0 ? available.width / FRAME.width : 1,
    available.height > 0 ? available.height / FRAME.height : 1
  );

  return (
    <div ref={rootRef}>
      <div ref={headRef} style={{ marginBottom: HEAD_GAP }}>
        <div style={{ fontSize: 13, fontWeight: 650, color: "#303030" }}>
          {I18n.t("live_widget_preview.live_preview")}
        </div>
        <div style={{ fontSize: 12, color: "#616161", marginTop: 4 }}>
          {I18n.t("live_widget_preview.click_through_test_otp")}{" "}
          <span
            style={{
              fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
              fontWeight: 700,
              fontSize: 12,
              color: "#303030",
              background: "#f1f1f1",
              border: "1px solid #d9d9d9",
              borderRadius: 4,
              padding: "1px 6px",
              letterSpacing: "0.5px",
            }}
          >
            1234
          </span>
        </div>
        <div style={{ fontSize: 12, color: "#616161", marginTop: 2 }}>
          {I18n.t("live_widget_preview.nothing_here_is_sent_to_customers")}
        </div>
      </div>
      <div ref={boxRef} style={{ width: "100%", height: FRAME.height * scale }}>
        <div
          style={{
            width: FRAME.width,
            height: FRAME.height,
            transform: `scale(${scale})`,
            transformOrigin: "top left",
            border: "1px solid #c9cccf",
            borderRadius: 18,
            overflow: "hidden",
            background: "#ffffff",
          }}
        >
          <iframe
            ref={frameRef}
            title={I18n.t("live_widget_preview.cod_king_widget_preview")}
            src={HOST_PATH}
            sandbox="allow-scripts allow-same-origin allow-forms allow-modals allow-popups"
            style={{
              width: "100%",
              height: "100%",
              border: "none",
              display: "block",
            }}
          />
        </div>
      </div>
    </div>
  );
};

export default LiveWidgetPreview;

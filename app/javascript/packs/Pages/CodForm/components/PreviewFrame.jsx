import React, { useEffect, useRef } from "react";

/**
 * The storefront-engine preview of ARCHITECTURE H.6: an isolated iframe
 * (`/cod_form/preview_frame`) that imports the real form bundle and mounts it
 * with fixture data. The admin posts the draft on every change, debounced
 * 150 ms. The designer's default preview is the React mock (FormMock); this
 * frame is offered next to it when the extension asset base is known.
 */
const PreviewFrame = ({ frameUrl, assetBase, form, button, texts, locale, device, view = "form", height = 640, title, onError }) => {
  const frameRef = useRef(null);
  const loadedRef = useRef(false);
  const latest = useRef(null);
  const typing = useRef(null);
  latest.current = { type: "codkf:preview", form, button, texts, locale, device, view };

  const send = () => {
    const frame = frameRef.current;
    if (!frame || !frame.contentWindow || !loadedRef.current) return;
    // Remember the admin field being typed in: a form bundle that focuses itself when it
    // re-mounts must not take the cursor away (see the blur handler below).
    const active = document.activeElement;
    typing.current =
      active && /^(INPUT|TEXTAREA)$/.test(active.tagName) ? { field: active, until: Date.now() + 1500 } : null;
    // The frame is sandboxed without allow-same-origin, so its origin is opaque.
    frame.contentWindow.postMessage(latest.current, "*");
  };

  // The frame announces itself with `codkf:preview_ready`; `codkf:preview_error`
  // (no_asset_base | bundle | render) hands control back to the caller.
  useEffect(() => {
    const onMessage = (event) => {
      const frame = frameRef.current;
      if (!frame || event.source !== frame.contentWindow || !event.data) return;
      if (event.data.type === "codkf:preview_ready") {
        loadedRef.current = true;
        send();
      } else if (event.data.type === "codkf:preview_error" && onError) {
        onError(event.data.reason || "render");
      }
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [onError]);

  // If the preview grabs the focus right after an update, hand it back to the field.
  useEffect(() => {
    const onBlur = () => {
      const guard = typing.current;
      if (!guard || Date.now() > guard.until) return;
      setTimeout(() => {
        if (document.activeElement === frameRef.current && guard.field.isConnected) guard.field.focus();
      }, 0);
    };
    window.addEventListener("blur", onBlur);
    return () => window.removeEventListener("blur", onBlur);
  }, []);

  useEffect(() => {
    const timer = setTimeout(send, 150);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [form, button, texts, locale, device, view]);

  if (!frameUrl || !assetBase) return null;
  const separator = frameUrl.includes("?") ? "&" : "?";
  const src = `${frameUrl}${separator}asset_base=${encodeURIComponent(assetBase)}`;

  return (
    <iframe
      ref={frameRef}
      title={title || "COD Form preview"}
      src={src}
      sandbox="allow-scripts"
      style={{ width: "100%", height, border: 0, display: "block", background: "transparent" }}
      onLoad={() => {
        loadedRef.current = true;
        send();
      }}
    />
  );
};

export default PreviewFrame;

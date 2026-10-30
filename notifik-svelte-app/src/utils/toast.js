import { loadToastify } from "./toastLoader.js";

const ICONS = { success: "✅", error: "❌", warning: "⚠️", info: "" };

async function show(message, type) {
  const text = String(message || "").trim();
  if (!text) return false;
  const Toastify = await loadToastify();
  if (!Toastify) return false;

  const icon = ICONS[type] || "";
  const container =
    typeof document !== "undefined"
      ? document.querySelector(".modal-card") ||
        document.querySelector(".modal-content")
      : null;

  Toastify({
    text: icon ? `${icon}  ${text}` : text,
    duration: 4000,
    gravity: "top",
    position: "center",
    close: false,
    stopOnFocus: true,
    escapeMarkup: true,
    selector: container || undefined,
    offset: { x: 0, y: 24 },
    style: {
      position: container ? "absolute" : "fixed",
      background: "#ffffff",
      color: "#1c1c1e",
      border: "1px solid #eceff4",
      borderRadius: "12px",
      boxShadow: "0 8px 24px rgba(15, 23, 42, 0.14)",
      padding: "12px 14px",
      fontSize: "14px",
      fontWeight: "400",
      lineHeight: "20px",
      fontFamily: "var(--font-family-base)",
      maxWidth: "360px",
      zIndex: "2147483647",
    },
  }).showToast();
  return true;
}

export const toast = {
  success: (m) => show(m, "success"),
  error: (m) => show(m, "error"),
  warning: (m) => show(m, "warning"),
  info: (m) => show(m, "info"),
};

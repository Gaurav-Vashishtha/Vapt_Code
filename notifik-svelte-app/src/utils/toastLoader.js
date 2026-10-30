const TOASTIFY_JS =
  "https://cdn.jsdelivr.net/npm/toastify-js@1.12.0/src/toastify.min.js";
const STYLE_ID = "codk-toastify-css";

const TOASTIFY_CSS = `
.toastify{padding:12px 20px;color:#fff;display:inline-block;box-shadow:0 3px 6px -1px rgba(0,0,0,.12),0 10px 36px -4px rgba(77,96,232,.3);background:linear-gradient(135deg,#73a5ff,#5477f5);position:fixed;opacity:0;transition:all .4s cubic-bezier(.215,.61,.355,1);border-radius:2px;cursor:pointer;text-decoration:none;max-width:calc(50% - 20px);z-index:2147483647}
.toastify.on{opacity:1}
.toast-close{background:transparent;border:0;color:#fff;cursor:pointer;font-family:inherit;font-size:1em;opacity:.4;padding:0 5px}
.toastify-right{right:15px}
.toastify-left{left:15px}
.toastify-top{top:-150px}
.toastify-bottom{bottom:-150px}
.toastify-rounded{border-radius:25px}
.toastify-avatar{width:1.5em;height:1.5em;margin:-7px 5px;border-radius:2px}
.toastify-center{margin-left:auto;margin-right:auto;left:0;right:0;max-width:fit-content;max-width:-moz-fit-content}
@media only screen and (max-width:360px){.toastify-right,.toastify-left{margin-left:auto;margin-right:auto;left:0;right:0;max-width:fit-content}}
`;

let pending = null;

function ensureCss() {
  if (typeof document === "undefined") return;
  if (document.getElementById(STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = TOASTIFY_CSS;
  document.head.appendChild(style);
}

export function loadToastify() {
  if (typeof window === "undefined") return Promise.resolve(null);
  if (window.Toastify) {
    ensureCss();
    return Promise.resolve(window.Toastify);
  }
  if (pending) return pending;

  pending = new Promise((resolve) => {
    ensureCss();
    const existing = document.querySelector(`script[src="${TOASTIFY_JS}"]`);
    const script = existing || document.createElement("script");

    const done = () => resolve(window.Toastify || null);
    const fail = () => {
      pending = null;
      resolve(null);
    };

    script.addEventListener("load", done, { once: true });
    script.addEventListener("error", fail, { once: true });

    if (!existing) {
      script.src = TOASTIFY_JS;
      script.async = true;
      document.head.appendChild(script);
    }
  });

  return pending;
}

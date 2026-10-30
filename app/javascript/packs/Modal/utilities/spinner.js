import { SELECTORS } from "./selectors";

export function showSpinner() {
  function createLoaderElement() {
    const loader = document.createElement("span");
    loader.className = "button-loader";
    loader.style.marginLeft = "10px";
    loader.innerHTML = `
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="16"
      height="16"
      viewBox="0 0 24 24"
    >
      <path
        fill="currentColor"
        d="M12,4a8,8,0,0,1,7.89,6.7A1.53,1.53,0,0,0,21.38,12h0a1.5,1.5,0,0,0,1.48-1.75,11,11,0,0,0-21.72,0A1.5,1.5,0,0,0,2.62,12h0a1.53,1.53,0,0,0,1.49-1.3A8,8,0,0,1,12,4Z"
      >
        <animateTransform
          attributeName="transform"
          dur="0.75s"
          repeatCount="indefinite"
          type="rotate"
          values="0 12 12;360 12 12"
        />
      </path>
    </svg>
  `;
    return loader;
  }

  Object.values(SELECTORS)
    .flat()
    .forEach((selector) => {
      const paymentButton = document.querySelector(selector);
      if (paymentButton && !paymentButton.querySelector(".button-loader")) {
        // Only add the loader if one does not already exist
        const loader = createLoaderElement();
        paymentButton.appendChild(loader);
        loader.style.display = "none";
        // Disable the button and change the cursor

        paymentButton.style.cursor = "not-allowed";
        // paymentButton.style.opacity = "0.6"; // Optional: reduce opacity to indicate it's disabled
      }
    });
}

export function hideSpinner() {
  Object.values(SELECTORS)
    .flat()
    .forEach((selector) => {
      const paymentButton = document.querySelector(selector);
      if (paymentButton) {
        // Find and remove the loader if it exists
        const loader = paymentButton.querySelector(".button-loader");
        if (loader) {
          loader.remove();
        }

        // Re-enable the button and reset the cursor
        paymentButton.disabled = false;
        paymentButton.style.cursor = "pointer";
        paymentButton.style.opacity = "1"; // Reset opacity
      }
    });
}

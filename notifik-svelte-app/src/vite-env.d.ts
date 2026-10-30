/// <reference types="svelte" />
/// <reference types="vite/client" />

// Extend Window interface for our custom properties
interface Window {
  codkingSvelteReady?: boolean;
  parent: Window & {
    codkingSvelteReady?: boolean;
    dispatchEvent: (event: Event) => boolean;
  };
}


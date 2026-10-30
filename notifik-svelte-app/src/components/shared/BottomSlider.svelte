<script>
  /**
   * BottomSlider - Reusable bottom/left slider component
   * Slides up from bottom on mobile, slides in from left on desktop.
   * Uses Svelte transitions for enter/exit (slide-up + fade) for a premium feel.
   */
  import { createEventDispatcher } from "svelte";
  import { onMount, onDestroy } from "svelte";
  import { fade } from "svelte/transition";
  import {
    slideFromBottom,
    MOTION_SHEET_MS,
    getBackdropDuration,
    getSheetDuration,
  } from "../../utils/transitions.js";
  import { lockBodyScroll, unlockBodyScroll } from "../../utils/bodyScrollLock.js";
  import "../../styles/components/shared/BottomSlider.css";
  import "../../styles/components/shared/BottomSlider.mobile.css";
  import "../../styles/components/shared/BottomSlider.desktop.css";

  let didLock = false;
  /** Timeout for delaying scroll unlock until sheet close animation finishes */
  let unlockTimeoutId = null;

  export let open = false;
  export let showBackdrop = true;
  export let backdropClickable = true;
  export let showCloseButton = true;
  export let title = "";
  export let subtitle = "";
  // Default to auto height so the slider shrink‑wraps content,
  // while CSS enforces a max-height with a visible gap at the top.
  export let height = "auto";
  export let contentScrollable = true; // when false, consumer controls inner scrolling
  // Close affordance: "x" = floating X above the sheet; "back" = chevron in the
  // header's top-left (used for full-screen mobile flows).
  export let closeButtonStyle = "x";
  // On small screens (< sm), let the sheet take the full viewport height.
  export let mobileFullHeight = false;

  // Allow the consumer to request a shrink-wrapped slider for small content
  const isAutoHeight = () =>
    height === "auto" || height === "fit-content" || height === "content";

  const dispatch = createEventDispatcher();

  function handleBackdropClick() {
    if (backdropClickable && open) {
      dispatch("close");
    }
  }

  function handleClose() {
    dispatch("close");
  }

  function handleKeydown(e) {
    if (e.key === "Escape" && open) {
      handleClose();
    }
  }

  // Lock/unlock body scroll. Unlock is delayed so it runs after close animation.
  $: {
    if (open && !didLock) {
      if (unlockTimeoutId != null) {
        clearTimeout(unlockTimeoutId);
        unlockTimeoutId = null;
      }
      lockBodyScroll();
      if (mobileFullHeight && typeof document !== "undefined") {
        document.documentElement.dataset.fullHeightSliderOpen = "true";
      }
      didLock = true;
    } else if (!open && didLock) {
      unlockTimeoutId = setTimeout(() => {
        unlockTimeoutId = null;
        unlockBodyScroll();
        if (mobileFullHeight && typeof document !== "undefined") {
          delete document.documentElement.dataset.fullHeightSliderOpen;
        }
        didLock = false;
      }, getSheetDuration());
    }
  }

  onMount(() => {
    if (typeof document !== "undefined") {
      document.addEventListener("keydown", handleKeydown);
    }
  });

  onDestroy(() => {
    if (unlockTimeoutId != null) {
      clearTimeout(unlockTimeoutId);
      unlockTimeoutId = null;
    }
    if (didLock) {
      unlockBodyScroll();
      if (mobileFullHeight && typeof document !== "undefined") {
        delete document.documentElement.dataset.fullHeightSliderOpen;
      }
      didLock = false;
    }
    if (typeof document !== "undefined") {
      document.removeEventListener("keydown", handleKeydown);
    }
  });
</script>

{#if open}
  <!-- Backdrop overlay: fade in/out -->
  {#if showBackdrop}
    <div
      class="bottom-slider-backdrop"
      role="button"
      tabindex="0"
      aria-label="Close slider"
      on:click={handleBackdropClick}
      on:keydown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          handleBackdropClick();
        }
      }}
      transition:fade={{ duration: getBackdropDuration() }}
    ></div>
  {/if}

  <!-- Slider panel: slide up from bottom on enter, slide down on exit -->
  <div
    class="bottom-slider rounded-t-2xl bg-white"
    data-open={open}
    data-auto-height={isAutoHeight()}
    data-full-height={mobileFullHeight}
    data-close-style={closeButtonStyle}
    style="--slider-height: {height};"
    transition:slideFromBottom={{ duration: MOTION_SHEET_MS }}
  >
    <!-- Floating X close button (above the sheet) – only in "x" mode -->
    {#if showCloseButton && closeButtonStyle !== "back"}
      <button
        class="slider-close-button slider-close-button--outside"
        on:click={handleClose}
        aria-label="Close slider"
        type="button"
      >
        <svg
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <line x1="18" y1="6" x2="6" y2="18"></line>
          <line x1="6" y1="6" x2="18" y2="18"></line>
        </svg>
      </button>
    {/if}
    <!-- Header (optional, only for title) -->
    {#if title}
      <div class="slider-header">
        {#if showCloseButton && closeButtonStyle === "back"}
          <button
            class="slider-back-button"
            on:click={handleClose}
            aria-label="Go back"
            type="button"
          >
            <svg
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <polyline points="15 18 9 12 15 6"></polyline>
            </svg>
          </button>
        {/if}
        <div class="slider-header-content">
          <h3 class="slider-title">{title}</h3>
          {#if subtitle}
            <p class="slider-subtitle">{subtitle}</p>
          {/if}
        </div>
      </div>
    {/if}

    <!-- Content Area - Tailwind rounded/overflow so corners clip without extra layers -->
    <div
      class="slider-content rounded-t-2xl overflow-x-hidden bg-white {contentScrollable
        ? 'overflow-y-auto'
        : 'overflow-hidden'}"
      class:slider-content--scrollable={contentScrollable}
      class:slider-content--no-scroll={!contentScrollable}
    >
      <slot />
    </div>
  </div>
{/if}

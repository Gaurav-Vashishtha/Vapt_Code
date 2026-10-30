<script>
  /**
   * Sheet - generic dialog that rises from the bottom of the popup.
   *
   * Stays mounted through the exit animation so closing is as smooth as
   * opening, and shares the global scroll lock with BottomSlider so nested
   * overlays don't unfreeze the screen behind them.
   *
   * `dismiss`/`goBack` avoid an `on` prefix because the build preprocessor
   * rewrites `onX=` attributes into `on:x=` directives, which never reach a
   * component as a prop.
   *
   * @component
   */
  import { onDestroy, onMount } from "svelte";
  import {
    lockBodyScroll,
    unlockBodyScroll,
  } from "../../utils/bodyScrollLock.js";

  let {
    open = false,
    title = "",
    subtitle = "",
    closeLabel = "Close",
    showCloseButton = true,
    showBackButton = false,
    headerBorder = true,
    dismissOnBackdrop = true,
    bodyPadded = true,
    /** @type {"sunken" | "card"} */
    bodySurface = "sunken",
    headerBanner = false,
    headerBackground = "",
    headerTextColor = "",
    dismiss = () => {},
    goBack = null,
    header = undefined,
    children = undefined,
    footer = undefined,
  } = $props();

  let mounted = $state(false);
  let locked = false;

  $effect(() => {
    if (!open) return;
    mounted = true;
    if (!locked) {
      lockBodyScroll();
      locked = true;
    }
  });

  function release() {
    if (!locked) return;
    unlockBodyScroll();
    locked = false;
  }

  function handleSheetAnimationEnd(event) {
    if (event.target !== event.currentTarget || open) return;
    mounted = false;
    release();
  }

  function handleBackdrop() {
    if (dismissOnBackdrop) dismiss();
  }

  function handleKeydown(event) {
    if (event.key === "Escape" && open) dismiss();
  }

  onMount(() => {
    if (typeof document !== "undefined") {
      document.addEventListener("keydown", handleKeydown);
    }
  });

  onDestroy(() => {
    release();
    if (typeof document !== "undefined") {
      document.removeEventListener("keydown", handleKeydown);
    }
  });
</script>

{#if mounted}
  <div class="ck-sheet-root" data-open={open}>
    <button
      type="button"
      class="ck-sheet-backdrop {open ? 'ck-backdrop-in' : 'ck-backdrop-out'}"
      aria-label={closeLabel}
      onclick={handleBackdrop}
    ></button>

    {#if showCloseButton}
      <button
        type="button"
        class="ck-sheet-close {open ? 'ck-pop-in' : 'ck-pop-out'}"
        aria-label={closeLabel}
        onclick={dismiss}
      >
        <svg
          viewBox="0 0 24 24"
          width="16"
          height="16"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <line x1="18" y1="6" x2="6" y2="18" />
          <line x1="6" y1="6" x2="18" y2="18" />
        </svg>
      </button>
    {/if}

    <div
      class="ck-sheet {open ? 'ck-sheet-in' : 'ck-sheet-out'}"
      role="dialog"
      aria-modal="true"
      aria-label={typeof title === "string" ? title : undefined}
      onanimationend={handleSheetAnimationEnd}
    >
      {#if header || title}
        <div
          class="ck-sheet__header"
          class:ck-sheet__header--bordered={headerBorder}
          class:ck-sheet__header--colored={headerBanner}
          style={[
            headerBackground ? `background: ${headerBackground};` : "",
            headerTextColor ? `--ck-sheet-header-fg: ${headerTextColor};` : "",
          ].join(" ")}
        >
          {#if showBackButton && goBack}
            <button
              type="button"
              class="ck-sheet__back"
              aria-label="Go back"
              onclick={goBack}
            >
              <svg
                viewBox="0 0 24 24"
                width="20"
                height="20"
                fill="none"
                stroke="currentColor"
                stroke-width="2.5"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <polyline points="15 18 9 12 15 6" />
              </svg>
            </button>
          {/if}
          {#if header}
            {@render header()}
          {:else}
            <div class="ck-sheet__heading">
              <h2 class="ck-sheet__title">{title}</h2>
              {#if subtitle}
                <p class="ck-sheet__subtitle">{subtitle}</p>
              {/if}
            </div>
          {/if}
        </div>
      {/if}

      <div
        class="ck-sheet__body ck-sheet__body--{bodySurface}"
        class:ck-sheet__body--padded={bodyPadded}
      >
        {@render children?.()}
      </div>

      {#if footer}
        <div class="ck-sheet__footer">{@render footer()}</div>
      {/if}
    </div>
  </div>
{/if}

<style>
  .ck-sheet-root {
    position: fixed;
    inset: 0;
    z-index: 2147483646;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: flex-end;
    isolation: isolate;
    pointer-events: auto;
  }

  .ck-sheet-backdrop {
    position: absolute;
    inset: 0;
    padding: 0;
    border: none;
    cursor: default;
    background: var(--color-overlay);
    backdrop-filter: blur(6px);
    -webkit-backdrop-filter: blur(6px);
  }

  .ck-sheet-close {
    position: relative;
    z-index: 1;
    margin-bottom: 10px;
    width: 32px;
    height: 32px;
    padding: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    border: none;
    border-radius: var(--radius-pill);
    cursor: pointer;
    color: var(--surface-card);
    background: rgba(28, 28, 30, 0.85);
  }

  .ck-sheet-close:hover {
    background: var(--color-text-primary);
  }

  .ck-sheet-close:active {
    transform: scale(var(--press-scale));
  }

  .ck-sheet {
    position: relative;
    z-index: 1;
    display: flex;
    flex-direction: column;
    width: 100%;
    max-width: 725px;
    max-height: 88%;
    min-height: 0;
    overflow: hidden;
    box-sizing: border-box;
    background: var(--surface-sunken);
    border-radius: var(--radius-lg) var(--radius-lg) 0 0;
    box-shadow: 0 -6px 30px rgba(17, 17, 17, 0.12);
  }

  .ck-sheet__header {
    position: sticky;
    top: 0;
    z-index: 1;
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-shrink: 0;
    padding: var(--space-3) var(--space-4);
    background: var(--surface-card);
  }

  .ck-sheet__header--bordered {
    border-bottom: 1px solid var(--hairline);
  }

  .ck-sheet__header--colored {
    background: linear-gradient(135deg, #1a1a1a 0%, #000000 50%, #1a1a1a 100%);
    color: var(--ck-sheet-header-fg, #ffffff);
  }

  .ck-sheet__header--colored .ck-sheet__title,
  .ck-sheet__header--colored .ck-sheet__subtitle,
  .ck-sheet__header--colored .ck-sheet__back {
    color: var(--ck-sheet-header-fg, #ffffff);
  }

  .ck-sheet__back {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    margin-left: -4px;
    padding: 0;
    flex-shrink: 0;
    border: none;
    background: transparent;
    color: var(--color-text-primary);
    cursor: pointer;
  }

  .ck-sheet__heading {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .ck-sheet__title {
    margin: 0;
    font-size: var(--font-size-base);
    font-weight: var(--font-weight-semibold);
    line-height: var(--line-height-normal);
  }

  .ck-sheet__subtitle {
    margin: 0;
    font-size: var(--font-size-xs);
    font-weight: var(--font-weight-regular);
    line-height: var(--line-height-normal);
    color: var(--color-text-muted);
  }

  .ck-sheet__body {
    display: flex;
    flex-direction: column;
    min-height: 0;
    overflow-y: auto;
    overflow-x: hidden;
    overscroll-behavior: contain;
    -webkit-overflow-scrolling: touch;
  }

  .ck-sheet__body--sunken {
    background: var(--surface-sunken);
  }

  .ck-sheet__body--card {
    background: var(--surface-card);
  }

  .ck-sheet__body--padded {
    gap: var(--space-3);
    padding: var(--space-2);
    padding-bottom: 0;
  }

  .ck-sheet__footer {
    flex-shrink: 0;
    padding: var(--space-3) var(--space-4);
    padding-bottom: calc(env(safe-area-inset-bottom, 0px) + var(--space-3));
    background: var(--surface-card);
    border-top: 1px solid var(--hairline);
  }

  @media (min-width: 481px) {
    .ck-sheet-root {
      position: absolute;
    }
  }
</style>

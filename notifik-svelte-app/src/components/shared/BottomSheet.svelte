<script>
  /**
   * BottomSheet - Reusable bottom sheet component with slide-up animation
   * @component
   */
  import { createEventDispatcher } from "svelte";
  import { onMount, onDestroy } from "svelte";
  import "../../styles/components/shared/BottomSheet.css";
  import "../../styles/components/shared/BottomSheet.mobile.css";
  import "../../styles/components/shared/BottomSheet.desktop.css";

  export let open = false;
  export let maxWidth = 474;
  export let maxHeight = "65vh";
  export let minHeight = "500px";
  export let showBackdrop = true;
  export let backdropClickable = true;
  export let showHandle = true;
  export let blendWithParent = false; // Seamless mode for OTP sheet

  const dispatch = createEventDispatcher();

  // Lock body scroll when bottom sheet is open
  function lockBodyScroll() {
    if (typeof document !== "undefined") {
      const scrollY = window.scrollY;
      document.body.style.position = "fixed";
      document.body.style.top = `-${scrollY}px`;
      document.body.style.width = "100%";
      document.body.style.overflow = "hidden";
      document.documentElement.style.overflow = "hidden";
    }
  }

  // Unlock body scroll when bottom sheet is closed
  function unlockBodyScroll() {
    if (typeof document !== "undefined") {
      const scrollY = document.body.style.top;
      document.body.style.position = "";
      document.body.style.top = "";
      document.body.style.width = "";
      document.body.style.overflow = "";
      document.documentElement.style.overflow = "";
      if (scrollY) {
        window.scrollTo(0, parseInt(scrollY || "0") * -1);
      }
    }
  }

  // Prevent scroll propagation to body when at scroll boundaries
  function handleWheel(e) {
    const bottomSheet = e.currentTarget;
    if (!bottomSheet) return;

    const { scrollTop, scrollHeight, clientHeight } = bottomSheet;
    const isAtTop = scrollTop <= 0;
    const isAtBottom = scrollTop + clientHeight >= scrollHeight - 1;

    // If at top and scrolling up, or at bottom and scrolling down, prevent default
    if ((isAtTop && e.deltaY < 0) || (isAtBottom && e.deltaY > 0)) {
      e.preventDefault();
      e.stopPropagation();
    }
  }

  function handleBackdropClick() {
    if (backdropClickable && open) {
      dispatch("close");
    }
  }

  function handleKeydown(e) {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      if (backdropClickable && open) {
        dispatch("close");
      }
    }
  }

  // Lock/unlock body scroll based on open state
  $: if (open) {
    lockBodyScroll();
  } else {
    unlockBodyScroll();
  }

  onDestroy(() => {
    unlockBodyScroll();
  });
</script>

{#if open}
  <!-- Backdrop overlay -->
  {#if showBackdrop}
    <div
      class="bottom-sheet-backdrop"
      role="button"
      tabindex="0"
      aria-label="Close bottom sheet"
      on:click={handleBackdropClick}
      on:keydown={handleKeydown}
    ></div>
  {/if}

  <!-- Bottom Sheet -->
  <div
    class="bottom-sheet"
    class:bottom-sheet--blend={blendWithParent}
    data-open={open}
    style="max-width: {maxWidth}px; width: {maxWidth}px; max-height: {maxHeight}; min-height: {minHeight};"
    on:wheel={handleWheel}
  >
    {#if showHandle}
      <div class="bottom-sheet-handle"></div>
    {/if}
    <div
      class="bottom-sheet-content"
      class:bottom-sheet-content--blend={blendWithParent}
    >
      <slot />
    </div>
  </div>
{/if}

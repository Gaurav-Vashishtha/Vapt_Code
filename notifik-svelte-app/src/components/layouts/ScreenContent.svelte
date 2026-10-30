<script>
  /**
   * ScreenContent - Scrollable content area wrapper
   * Provides consistent padding and scrolling behavior
   */
  import { onMount } from "svelte";
  import "../../styles/components/layouts/ScreenContent.css";

  /** Edge-to-edge, unpadded content — used by full-screen loading states. */
  export let fullBleed = false;

  let contentElement;
  let hasScrollbar = false;

  function checkScrollbar() {
    if (!contentElement) return;

    // Check if scrollbar is present (scrollHeight > clientHeight)
    const hasVerticalScrollbar =
      contentElement.scrollHeight > contentElement.clientHeight;

    if (hasVerticalScrollbar !== hasScrollbar) {
      hasScrollbar = hasVerticalScrollbar;
      if (hasScrollbar) {
        contentElement.classList.add("has-scrollbar");
      } else {
        contentElement.classList.remove("has-scrollbar");
      }
    }
  }

  onMount(() => {
    if (!contentElement) return;

    // Check initially
    checkScrollbar();

    // Watch for content changes
    const resizeObserver = new ResizeObserver(() => {
      checkScrollbar();
    });
    resizeObserver.observe(contentElement);

    // Also check on scroll (in case content changes)
    contentElement.addEventListener("scroll", checkScrollbar, {
      passive: true,
    });

    return () => {
      resizeObserver.disconnect();
      if (contentElement) {
        contentElement.removeEventListener("scroll", checkScrollbar);
      }
    };
  });
</script>

<div
  class="screen-content"
  class:screen-content--full-bleed={fullBleed}
  bind:this={contentElement}
>
  <slot />
</div>

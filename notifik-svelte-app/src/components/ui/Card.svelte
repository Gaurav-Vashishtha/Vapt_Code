<script>
  /**
   * Card - generic surface primitive.
   *
   * @component
   * @property {"elevated" | "flat" | "sunken" | "soft"} [variant]
   * @property {"none" | "sm" | "snug" | "md" | "lg"} [padding]
   * @property {boolean} [stack] - lay children out as a spaced column
   * @property {boolean} [interactive] - renders a button with press feedback
   * @property {"none" | "top" | "bottom"} [attach] - squares off the edge another surface joins
   * @property {() => void} [press] - click handler; named without an `on` prefix
   *   because the build preprocessor rewrites `onX=` attributes into `on:x=`
   *   directives, which never reach a component as a prop.
   */
  let {
    variant = "elevated",
    padding = "md",
    interactive = false,
    attach = "none",
    stack = false,
    class: className = "",
    ariaLabel = undefined,
    testId = undefined,
    press = undefined,
    header = undefined,
    children = undefined,
    footer = undefined,
    ...rest
  } = $props();
</script>

<svelte:element
  this={interactive ? "button" : "div"}
  class="ck-card ck-card--{variant} ck-card--pad-{padding} ck-card--attach-{attach} {className}"
  class:ck-card--interactive={interactive}
  class:ck-card--stack={stack}
  aria-label={ariaLabel}
  data-testid={testId}
  onclick={press}
  {...interactive ? { type: "button" } : {}}
  {...rest}
>
  {#if header}
    <div class="ck-card__header">{@render header()}</div>
  {/if}
  {@render children?.()}
  {#if footer}
    <div class="ck-card__footer">{@render footer()}</div>
  {/if}
</svelte:element>

<style>
  .ck-card {
    display: block;
    width: 100%;
    min-width: 0;
    box-sizing: border-box;
    margin: 0;
    text-align: left;
    color: var(--color-text-primary);
    font-family: var(--font-family-base);
    background: var(--surface-card, #ffffff);
    box-shadow: 4px 4px 11px 0 #d0dbf726, -2px -2px 10px 0 #d0dbf726;
    border-radius: var(--radius-md);
  }

  .ck-card--elevated {
    box-shadow: var(--shadow-card-soft);
  }

  .ck-card--flat {
    box-shadow: none;
  }

  .ck-card--sunken {
    background: var(--surface-sunken);
    border-color: transparent;
    box-shadow: none;
  }

  .ck-card--soft {
    border: 0.75px solid color-mix(in srgb, var(--color-blue) 10%, transparent);
    border-radius: var(--radius-base);
    box-shadow:
      4px 4px 11px 0 rgba(208, 219, 247, 0.15),
      -2px -2px 10px 0 rgba(208, 219, 247, 0.15);
  }

  .ck-card--stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .ck-card--pad-none {
    padding: 0;
  }

  .ck-card--pad-sm {
    padding: var(--space-2) var(--space-3);
  }

  .ck-card--pad-snug {
    padding: var(--space-3);
  }

  .ck-card--pad-md {
    padding: var(--space-3) var(--space-4);
  }

  .ck-card--pad-lg {
    padding: var(--space-4) var(--space-5);
  }

  .ck-card--attach-bottom {
    border-bottom-left-radius: 0;
    border-bottom-right-radius: 0;
    border-bottom: none;
  }

  .ck-card--attach-top {
    border-top-left-radius: 0;
    border-top-right-radius: 0;
    border-top: none;
  }

  .ck-card--interactive {
    cursor: pointer;
    outline: none;
    -webkit-appearance: none;
    appearance: none;
    transition:
      background-color var(--motion-fast) var(--ease-smooth),
      box-shadow var(--motion-fast) var(--ease-smooth),
      transform var(--motion-fast) var(--ease-smooth);
  }

  .ck-card--interactive:active {
    transform: scale(var(--press-scale));
  }

  .ck-card__header {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    margin-bottom: var(--space-2);
  }

  .ck-card__footer {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin-top: var(--space-3);
  }

  @media (prefers-reduced-motion: reduce) {
    .ck-card--interactive {
      transition: none;
    }
    .ck-card--interactive:active {
      transform: none;
    }
  }
</style>

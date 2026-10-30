<script>
  export let variant = "primary"; // 'primary' | 'secondary' | 'outline'
  export let loading = false;
  // Optional text shown next to the spinner while loading (default: spinner only).
  export let loadingLabel = "";
  export let disabled = false;
  export let fullWidth = true; // Defaults to true to match the "block" feel usually desired
  export let icon = null; // HTML string (backward compatible)

  // Inline overrides
  export let backgroundColor = null;
  export let hoverBackground = null;
  export let textColor = null;
  export let borderRadius = null;
  export let padding = null;
  export let height = null;
  export let border = null; // e.g. "1px solid transparent"

  $: defaults = (() => {
    if (variant === "secondary") {
      return {
        bg: "transparent",
        hoverBg: "#f8f8f8",
        color: "#404040",
      };
    }

    if (variant === "outline") {
      return {
        bg: "#ffffff",
        hoverBg: "#f8f8f8",
        color: "#404040",
      };
    }

    // primary
    return {
      bg: "#000000",
      hoverBg: "#1a1a1a",
      color: "#ffffff",
      borderColor: "transparent",
    };
  })();

  // Use pure inline styles - no CSS variables or Tailwind color classes
  $: buttonStyle = [
    `height: ${height ?? "40px"}`,
    `padding: ${padding ?? "8px 16px"}`,
    `border-radius: ${borderRadius ?? "6px"}`,
    `background-color: ${backgroundColor ?? defaults.bg}`,
    `color: ${textColor ?? defaults.color}`,
    `border: ${border ?? (variant === "primary" ? "none" : `1px solid ${defaults.borderColor}`)}`,
    `box-shadow: 0px 1px 4px rgba(25, 33, 61, 0.08)`,
    `display: flex`,
    `align-items: center`,
    `justify-content: center`,
    `gap: 8px`,
    `box-sizing: border-box`,
    `overflow: hidden`,
    `max-width: 100%`,
  ]
    .filter(Boolean)
    .join("; ");

  $: hoverStyle = `background-color: ${hoverBackground ?? defaults.hoverBg}`;
</script>

<button
  {...$$restProps}
  class={`codk-button font-medium text-[12px] leading-[21px]
  cursor-pointer
  hover:opacity-90 active:opacity-80
  disabled:opacity-60 disabled:cursor-not-allowed disabled:pointer-events-none ${
    fullWidth ? "w-full" : "w-auto"
  } ${$$restProps.class ?? ""}`.trim()}
  disabled={disabled || loading}
  type="button"
  style={buttonStyle}
  on:click
  on:mouseenter={(e) => {
    if (!disabled && !loading && hoverStyle) {
      e.currentTarget.style.backgroundColor =
        hoverBackground ?? defaults.hoverBg;
      e.currentTarget.style.boxShadow = "0px 6px 16px rgba(25, 33, 61, 0.12)";
    }
  }}
  on:mouseleave={(e) => {
    if (!disabled && !loading) {
      e.currentTarget.style.backgroundColor = backgroundColor ?? defaults.bg;
      e.currentTarget.style.boxShadow = "0px 1px 4px rgba(25, 33, 61, 0.08)";
    }
  }}
  on:mousedown={(e) => {
    if (!disabled && !loading) {
      e.currentTarget.style.transform = "scale(0.99)";
      e.currentTarget.style.boxShadow = "0px 2px 8px rgba(25, 33, 61, 0.12)";
    }
  }}
  on:mouseup={(e) => {
    if (!disabled && !loading) {
      e.currentTarget.style.transform = "scale(1)";
    }
  }}
  aria-busy={loading ? "true" : "false"}
>
  {#if loading}
    <span
      class="codk-button-spinner"
      aria-hidden="true"
    ></span>
    {#if loadingLabel}
      <span
        class="codk-button-label"
        style={`color: ${textColor ?? defaults.color};`}
      >{loadingLabel}</span>
    {/if}
  {:else}
    {#if $$slots.icon || icon}
      <span
        class="codk-button-icon"
      >
        {#if $$slots.icon}
          <slot name="icon" />
        {:else}
          <span class="codk-button-icon-html">
            {@html icon}
          </span>
        {/if}
      </span>
    {/if}
    <span
      class="codk-button-label"
      style={`color: ${textColor ?? defaults.color};`}
    ><slot /></span
    >
  {/if}
</button>

<style>
  /* Icon + label are a single centered group (no flex-grow on label) */
  .codk-button-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 16px;
    height: 16px;
    min-width: 16px;
    max-width: 16px;
    flex-shrink: 0;
    overflow: hidden;
    box-sizing: border-box;
  }
  .codk-button-icon-html {
    display: inline-block;
    width: 100%;
    height: 100%;
    overflow: hidden;
  }
  .codk-button-label {
    white-space: nowrap;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  /* When there's an icon, label doesn't grow so icon+text stay centered as one unit */
  .codk-button:has(.codk-button-icon) .codk-button-label {
    flex: 0 1 auto;
  }
  /* When there's no icon, label can grow for long text */
  .codk-button:not(:has(.codk-button-icon)) .codk-button-label {
    flex: 1 1 auto;
  }

  .codk-button-spinner {
    display: inline-block;
    width: 18px;
    height: 18px;
    border: 2px solid currentColor;
    border-right-color: transparent;
    border-radius: 50%;
    animation: codk-spin 0.6s linear infinite;
    flex-shrink: 0;
  }

  .codk-button-spinner + .codk-button-label {
    margin-left: 8px;
  }
  @keyframes codk-spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>

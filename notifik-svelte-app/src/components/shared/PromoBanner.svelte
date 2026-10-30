<script>
  /**
   * PromoBanner - Reusable promotional banner component
   * Supports two variants: 'default' (red banner) and 'payment' (blue gradient banner)
   * @component
   */
  import "../../styles/components/shared/PromoBanner.css";

  export let text = "";
  export let variant = "default"; // 'default' | 'payment'
  export let emoji = "";
  export let description = "";
  export let showDescription = false;
  export let backgroundColor = ""; // Custom background color (overrides default)
  export let textColor = ""; // Custom text color (overrides default)

  // Show banner only if text is provided
  $: shouldShow = text && text.trim().length > 0;

  // Build custom style for background
  $: bgStyle = backgroundColor ? `background: ${backgroundColor};` : "";

  // Build custom style for text color
  $: textStyle = textColor ? `color: ${textColor};` : "";
</script>

{#if shouldShow}
  {#if variant === "payment"}
    <!-- Payment variant: Blue gradient banner with emoji and optional description -->
    <div class="promo-banner promo-banner--payment" style={bgStyle}>
      <div class="promo-banner__title">
        {#if emoji}
          <span class="promo-banner__emoji" style={textStyle}>{emoji}</span>
        {/if}
        <span class="promo-banner__text" style={textStyle}>{text}</span>
      </div>
      {#if showDescription && description}
        <div class="promo-banner__description" style={textStyle}>
          {description}
        </div>
      {/if}
    </div>
  {:else}
    <!-- Default variant: Red banner with centered text -->
    <div class="promo-banner promo-banner--default" style={bgStyle}>
      <div class="promo-banner__text" style={textStyle}>{text}</div>
    </div>
  {/if}
{/if}

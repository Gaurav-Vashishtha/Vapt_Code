<script>
  import "../../styles/components/shared/ErrorDisplay.css";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore);
  export let error = '';
  export let onRetry = null;
  export let compact = false;
</script>

{#if error}
  <div class="error-container" class:compact={compact}>
    <div class="error-icon">⚠️</div>
    <p class="error-message">{error}</p>
    {#if onRetry}
      <button class="retry-button" on:click={onRetry}>
        {T("try_again")}
      </button>
    {/if}
  </div>
{/if}

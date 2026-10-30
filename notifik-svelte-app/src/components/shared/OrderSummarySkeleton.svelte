<script>
  import Card from "../ui/Card.svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore);
</script>

<Card variant="flat" padding="md">
  <div class="os-skel-row">
    <span class="os-skel-title">{T("order_summary_title")}</span>
    <div class="os-skel-pricing">
      <span class="os-skel-bar os-skel-total"></span>
      <svg
        class="os-skel-chevron"
        width="16"
        height="16"
        viewBox="0 0 16 16"
        fill="none"
        aria-hidden="true"
      >
        <path
          d="m8 8.781 3.3-3.3.943.943L8 10.667 3.758 6.424l.943-.943z"
          fill="currentColor"
        />
      </svg>
    </div>
  </div>
</Card>

<style>
  .os-skel-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    min-width: 0;
  }

  .os-skel-title {
    font-size: var(--font-size-base);
    line-height: 22px;
    font-weight: var(--font-weight-semibold);
    color: var(--color-text-primary);
    white-space: nowrap;
  }

  .os-skel-pricing {
    display: flex;
    align-items: center;
    gap: 6px;
    flex-shrink: 0;
  }

  .os-skel-bar {
    display: block;
    border-radius: var(--radius-sm);
    background: linear-gradient(90deg, #eef1f6 25%, #e2e6ee 50%, #eef1f6 75%);
    background-size: 200% 100%;
    animation: os-skel-loading 1.5s ease-in-out infinite;
  }

  .os-skel-total {
    width: 64px;
    height: 16px;
  }

  .os-skel-chevron {
    width: 16px;
    height: 16px;
    flex-shrink: 0;
    color: var(--color-text-muted);
    transform: rotate(-90deg);
  }

  @keyframes os-skel-loading {
    0% {
      background-position: 200% 0;
    }
    100% {
      background-position: -200% 0;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .os-skel-bar {
      animation: none;
    }
  }
</style>

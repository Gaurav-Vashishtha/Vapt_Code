<script>
  export let count = 3;
</script>

<div class="po-skel">
  {#each Array(count) as _, i}
    <div class="po-skel-card">
      <div class="po-skel-radio">
        {#if i === Math.floor(count / 2)}
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="#404040"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M3 7h11v10H3z" />
            <path d="M14 10h4l3 3v4h-7" />
            <circle cx="7" cy="19" r="1.5" />
            <circle cx="17" cy="19" r="1.5" />
          </svg>
        {:else}
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="#404040"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <rect x="3" y="6" width="18" height="12" rx="2" />
            <path d="M3 10h18" />
            <path d="M7 15h4" />
          </svg>
        {/if}
      </div>
      <div class="po-skel-content">
        <span class="po-skel-bar po-skel-name"></span>
        <span class="po-skel-bar po-skel-desc"></span>
      </div>
      <span class="po-skel-bar po-skel-price"></span>
    </div>
  {/each}
</div>

<style>
  .po-skel {
    display: flex;
    flex-direction: column;
  }

  .po-skel-card {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 8px;
    min-height: 60px;
    border-top: 2px dashed var(--hairline);
    border-bottom: 2px dashed var(--hairline);
  }

  .po-skel-card:not(:first-child) {
    border-top: 0;
  }

  .po-skel-radio {
    width: 26px;
    height: 26px;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #ffffff;
    border-radius: 6px;
    border: 1px solid color-mix(in srgb, var(--color-blue) 20%, transparent);
  }

  .po-skel-content {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 6px;
    min-width: 0;
  }

  .po-skel-bar {
    display: block;
    border-radius: 4px;
    background: linear-gradient(90deg, #eef1f6 25%, #e2e6ee 50%, #eef1f6 75%);
    background-size: 200% 100%;
    animation: po-skel-loading 1.5s ease-in-out infinite;
  }

  .po-skel-name {
    width: 45%;
    height: 14px;
  }

  .po-skel-desc {
    width: 70%;
    height: 12px;
  }

  .po-skel-price {
    width: 56px;
    height: 18px;
    flex-shrink: 0;
  }

  @keyframes po-skel-loading {
    0% {
      background-position: 200% 0;
    }
    100% {
      background-position: -200% 0;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .po-skel-bar {
      animation: none;
    }
  }
</style>

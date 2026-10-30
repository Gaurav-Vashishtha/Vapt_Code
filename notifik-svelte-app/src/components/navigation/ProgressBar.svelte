<script>
  import "../../styles/components/navigation/ProgressBar.css";
  import "../../styles/components/navigation/ProgressBar.mobile.css";

  export let activeScreen = "mobile";
  export let screens = [
    { key: "mobile", label: "Mobile" },
    { key: "address", label: "Address" },
    { key: "pay", label: "Pay" },
  ];
</script>

{#if screens && screens.length > 1}
  <div class="progress-bar">
    {#each screens as screen, index}
      <div class="progress-item">
        <div
          class="screen-indicator"
          class:active={activeScreen === screen.key}
          class:completed={screens.findIndex((s) => s.key === activeScreen) >
            index}
        >
          <div class="screen-check">
            {#if screens.findIndex((s) => s.key === activeScreen) > index}
              <span class="checkmark">✓</span>
            {/if}
          </div>
          <div class="screen-label">{screen.label}</div>
        </div>
        {#if index < screens.length - 1}
          <div class="screen-connector"></div>
        {/if}
      </div>
    {/each}
  </div>
{/if}

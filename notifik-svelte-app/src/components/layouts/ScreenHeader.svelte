<script>
  /**
   * ScreenHeader - back action on the left, store identity centred.
   * @component
   */
  import "../../styles/components/layouts/ScreenHeader.css";
  import "../../styles/components/layouts/ScreenHeader.mobile.css";

  export let storeLogoUrl = null;
  export let storeName = "";
  export let storeTitle = "";
  /** @type {"wide" | "square" | ""} */
  export let storeLogoType = "";
  export let backAction = null;

  // A logo narrower than this (once scaled to the 30px header height) can't
  // carry the store identity on its own, so the title is shown next to it.
  const MIN_STANDALONE_LOGO_WIDTH = 96;

  let logoEl = null;
  let logoIsSmall = false;

  function measureLogo() {
    if (!logoEl || !logoEl.naturalWidth || !logoEl.naturalHeight) return;
    const height =
      logoEl.clientHeight || (storeLogoType === "square" ? 28 : 30);
    logoIsSmall =
      (logoEl.naturalWidth / logoEl.naturalHeight) * height <
      MIN_STANDALONE_LOGO_WIDTH;
  }

  $: if (logoEl && storeLogoUrl) measureLogo();

  $: showBrandTitle =
    (storeTitle || storeName) &&
    (!storeLogoUrl || storeLogoType === "square");
</script>

<div class="screen-header">
  <div class="header-bar">
    {#if backAction}
      <button
        class="header-action header-action--back"
        aria-label="Go back"
        on:click={backAction}
      >
        <svg
          width="18"
          height="16"
          viewBox="0 0 21 19"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            d="M17.0041 11C17.5563 10.9978 18.0022 10.5482 18 9.99594C17.9978 9.44366 17.5482 8.99777 16.9959 9.00001L17.0041 11ZM0.396178 9.36022C0.00724105 9.75232 0.00980865 10.3855 0.401913 10.7744L6.79163 17.1125C7.18373 17.5015 7.81689 17.4989 8.20583 17.1068C8.59477 16.7147 8.5922 16.0815 8.2001 15.6926L2.52035 10.0587L8.15422 4.37897C8.54315 3.98687 8.54059 3.35371 8.14848 2.96477C7.75638 2.57583 7.12322 2.5784 6.73428 2.9705L0.396178 9.36022ZM16.9959 9.00001L1.10209 9.06446L1.1102 11.0644L17.0041 11L16.9959 9.00001Z"
            fill="var(--header-icon-color)"
          />
        </svg>
      </button>
    {/if}

    <div class="header-brand">
      {#if storeLogoUrl}
        <img
          bind:this={logoEl}
          class="logo-image"
          class:logo-image--wide={storeLogoType === "wide"}
          class:logo-image--square={storeLogoType === "square"}
          src={storeLogoUrl}
          alt={storeName || storeTitle || "Store logo"}
          on:load={measureLogo}
        />
      {/if}
      {#if showBrandTitle}
        <div class="brand-title" title={storeTitle || storeName}>
          {storeTitle || storeName}
        </div>
      {/if}
    </div>
  </div>
</div>

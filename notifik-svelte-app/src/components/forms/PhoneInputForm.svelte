<script>
  /**
   * PhoneInputForm - Phone number input with country code selector
   * @component
   */
  import { createEventDispatcher } from "svelte";
  import {
    getCountryByKey,
    getCountryKeyByCode,
  } from "../../data/countries.js";
  import "../../styles/components/forms/PhoneInputForm.css";

  // Flag image CDN – consistent flag icons across all browsers/OS (avoids "IN"/"US" text on systems that don't render flag emojis)
  const FLAG_IMG_BASE = "https://flagcdn.com/w40";
  $: displayCountry = selectedCountry || filteredCountries[0] || null;
  $: displayCountryKey = displayCountry
    ? (
        displayCountry.key ||
        getCountryKeyByCode(displayCountry.code) ||
        ""
      ).toLowerCase()
    : "";
  $: selectedKey =
    displayCountry?.key || getCountryKeyByCode(selectedCountryCode) || "";

  export let phoneNumber = "";
  export let selectedCountryCode = "";
  export let selectedCountry = null;
  export let showDropdown = false;
  export let searchQuery = "";
  export let error = "";
  export let isValidNumber = false;
  export let filteredCountries = [];
  export let placeholder = "Phone number";
  /** Max length for phone input (e.g. 11 for Bangladesh, 15 default) */
  export let phoneMaxLength = 15;

  const dispatch = createEventDispatcher();

  // With a single available country there's nothing to pick, so the selector
  // is inert and the caret is hidden.
  $: canPickCountry = (filteredCountries?.length || 0) > 1;

  $: if (
    selectedCountryCode &&
    !selectedCountry &&
    filteredCountries.length > 0
  ) {
    selectedCountry =
      getCountryByKey(getCountryKeyByCode(selectedCountryCode)) ||
      filteredCountries[0] ||
      null;
  }

  function handleInput(e) {
    phoneNumber = e.target.value;
    dispatch("phoneChange", { phoneNumber, selectedCountryCode });
  }

  function handleCountrySelect(country) {
    selectedCountryCode = country.code;
    selectedCountry = country;
    showDropdown = false;
    searchQuery = "";
    dispatch("countryChange", { country, phoneNumber });
  }

  function handleNativeSelect(e) {
    const key = e.target.value;
    const country = filteredCountries.find((c) => c.key === key);
    if (country) handleCountrySelect(country);
  }

  function handleFocus() {
    dispatch("focus");
  }

  function handleBlur() {
    dispatch("blur");
  }

  function handleKeydown(e) {
    dispatch("keydown", e);
  }
</script>

<div class="phone-input-form">
  <div class="country-dropdown-container">
    <div class="phone-input-wrapper" class:has-value={phoneNumber.length > 0}>
      <div
        class="country-selector"
        class:country-selector--static={!canPickCountry}
      >
        <span class="country-flag" title={displayCountry?.name}>
          {#if displayCountryKey}
            <img
              src={`${FLAG_IMG_BASE}/${displayCountryKey}.png`}
              alt=""
              width="24"
              height="18"
              class="country-flag-img"
            />
          {:else}
            {displayCountry?.flag || ""}
          {/if}
        </span>
        <span class="country-code">+{displayCountry?.code || ""}</span>
        {#if canPickCountry}
          <svg
            class="caret-icon"
            width="16"
            height="16"
            viewBox="0 0 16 16"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              d="M4 6L8 10L12 6"
              stroke="#737373"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
          <select
            class="country-native-select"
            aria-label="Select country code"
            value={selectedKey}
            on:change={handleNativeSelect}
            on:click|stopPropagation
          >
            {#each filteredCountries as country}
              <option value={country.key}>
                {country.name} (+{country.code})
              </option>
            {/each}
          </select>
        {/if}
      </div>
      <div class="divider-line"></div>
      <div class="phone-input-container">
        <input
          type="tel"
          class="phone-input-field"
          class:error={error && !isValidNumber}
          {placeholder}
          value={phoneNumber}
          on:input={handleInput}
          on:keydown={handleKeydown}
          on:focus={handleFocus}
          on:blur={handleBlur}
          maxlength={phoneMaxLength}
        />
      </div>
    </div>
  </div>

</div>

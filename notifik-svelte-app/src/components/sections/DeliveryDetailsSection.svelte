<script module>
  let editHintSeen = false;
</script>

<script>
  import { onDestroy } from "svelte";
  import { appStore, actions } from "../../stores/buttonManager.js";
  import { settingsStore } from "../../stores/settingsStore.js";
  import otpStore, { otpStoreActions } from "../../stores/otpStore.js";
  import { getSessionValue, setSessionValue } from "../../services/sessionService.js";
  import BottomSlider from "../shared/BottomSlider.svelte";
  import Card from "../ui/Card.svelte";
  import "../../styles/components/sections/DeliveryDetailsSection.css";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore);
  /** @type {any} */
  export let selectedAddress = null;
  export let phoneNumber = "";
  export let customerEmail = "";

  $: otpState = $otpStore;
  $: displayEmail =
    customerEmail || otpState?.verifiedEmail || getSessionValue("customer-email") || "";
  $: availableShippingRates = otpState?.calculatedTaxData?.available_shipping_rates || [];
  $: selectedShippingHandle = otpState?.selectedShippingHandle || null;
  $: selectedShippingRate = availableShippingRates.find(
    (rate) => rate.handle === selectedShippingHandle,
  );
  $: hasMultipleShippingRates = availableShippingRates.length > 1;

  // Shipping method is shown only when BOTH conditions are true: isPrefilledAddressEnabled AND preV2ShowShippingInfo
  $: isPrefilledAddressEnabled = (() => {
    const s = otpState?.settings;
    return !!(
      s?.isPrefilledAddressEnabled === true || String(s?.isPrefilledAddressEnabled) === "true" ||
      s?.is_prefilled_address_enabled === true || String(s?.is_prefilled_address_enabled) === "true"
    );
  })();
  $: preV2ShowShippingInfo = (() => {
    const s = otpState?.settings;
    return s?.preV2ShowShippingInfo === true || String(s?.preV2ShowShippingInfo) === "true" ||
      s?.pre_v2_show_shipping_info === true || String(s?.pre_v2_show_shipping_info) === "true";
  })();
  $: showShippingMethod = isPrefilledAddressEnabled && preV2ShowShippingInfo;

  let shippingPickerOpen = false;

  const EDIT_HINT_MS = 2800;
  let showEditHint = false;
  let editHintTimer;

  function triggerEditHint() {
    if (editHintSeen) return;
    editHintSeen = true;
    showEditHint = true;
    editHintTimer = setTimeout(() => (showEditHint = false), EDIT_HINT_MS);
  }

  $: if (selectedAddress) triggerEditHint();

  onDestroy(() => clearTimeout(editHintTimer));

  function selectShipping(handle) {
    otpStore.setSelectedShippingHandle(handle);
    setSessionValue("selected_shipping_handle", handle);
    shippingPickerOpen = false;
  }

  $: currencyCode = otpState?.currentCartData?.currency || "INR";

  function formatShippingPrice(price) {
    const num = typeof price === "number" ? price : parseFloat(price) || 0;
    if (num === 0) return null;
    const symbol = currencyCode === "INR" ? "₹" : currencyCode + " ";
    return symbol + num.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  }
  function handleEdit() {
    const addresses = $appStore.addresses || [];
    const addressToEdit = selectedAddress
      ? addresses.find((addr) => addr.id === selectedAddress.id)
      : addresses.find((addr) => addr.id === $appStore.selectedAddressId);
    if (addressToEdit) {
      otpStoreActions.setIsEditAddress(true);
      otpStoreActions.setEditableAddress(addressToEdit);
    }
    actions.setScreen("address");
  }

  function formatAddress(address) {
    if (!address) return "";
    const normalizeFormatted = (value) => {
      if (!value) return "";
      if (Array.isArray(value)) {
        return value.filter(Boolean).map(String).join(", ").trim();
      }
      const str = String(value).trim();
      if (!str) return "";
      if (str.startsWith("[") && str.endsWith("]")) {
        try {
          const parsed = JSON.parse(str);
          if (Array.isArray(parsed)) {
            return parsed.filter(Boolean).map(String).join(", ").trim();
          }
          if (typeof parsed === "string") return parsed.trim();
        } catch {
        }
      }
      if (
        (str.startsWith('"') && str.endsWith('"')) ||
        (str.startsWith("'") && str.endsWith("'"))
      ) {
        return str.slice(1, -1).trim();
      }
      return str;
    };

    const formatted = normalizeFormatted(
      address.formatted || address.formatted_area,
    );
    if (formatted) return formatted;

    const parts = [];
    const address1 = address.address1 || address.address_1 || address.line1;
    const address2 = address.address2 || address.address_2 || address.line2;
    if (address1) parts.push(address1);
    if (address2) parts.push(address2);
    if (address.city) parts.push(address.city);
    if (address.province) parts.push(address.province);
    if (address.state) parts.push(address.state);
    if (address.zip) parts.push(address.zip);
    if (address.country) parts.push(address.country);
    if (address.country_name) parts.push(address.country_name);
    return parts.join(", ");
  }

  function formatPhone(phone) {
    if (!phone) return "";
    const cleaned = phone.toString().replace(/^\+*/, "").replace(/[^\d]/g, "");
    if (cleaned.length === 12 && cleaned.startsWith("91")) {
      return `+${cleaned.slice(0, 2)} ${cleaned.slice(2, 7)} ${cleaned.slice(7)}`;
    } else if (cleaned.length === 10) {
      return `+91 ${cleaned.slice(0, 5)} ${cleaned.slice(5)}`;
    }
    const phoneStr = phone.toString();
    if (phoneStr.startsWith("+")) {
      return phoneStr.replace(/^\++/, "+"); // Remove multiple + and keep single +
    }
    return `+${phoneStr}`;
  }
</script>

<div class="delivery-details-compact">
  {#if selectedAddress}
    <Card variant="elevated" padding="md" class="delivery-card">
      <div class="delivery-card-header">
        <span class="delivery-card-title">{T("delivery_card_title")}</span>
        <span class="delivery-change-wrap">
          {#if showEditHint}
            <span class="delivery-edit-hint" role="status" aria-live="polite">
              {T("delivery_edit_hint")}
            </span>
          {/if}
          <button
            type="button"
            class="delivery-change-btn hover:opacity-80"
            on:click={(e) => {
              e.preventDefault();
              e.stopPropagation();
              handleEdit();
            }}
          >
            {T("delivery_change")}
          </button>
        </span>
      </div>

      <div class="delivery-name-row">
        <span class="delivery-name">
          {selectedAddress.first_name || ""}
          {selectedAddress.last_name || ""}
        </span>
        <span class="delivery-tag">{selectedAddress.address_type || "Home"}</span>
      </div>

      <div
        class="delivery-address"
        title={formatAddress(selectedAddress) || "Address not available"}
      >
        {formatAddress(selectedAddress) || "Address not available"}
      </div>

      {#if phoneNumber || displayEmail}
        <div class="delivery-contact-row">
          {#if phoneNumber}
            <span class="delivery-contact delivery-contact--phone">
              <svg
                width="12"
                height="12"
                viewBox="0 0 12 12"
                fill="none"
                xmlns="http://www.w3.org/2000/svg"
              >
                <path
                  d="M2.96708 0.69934L3.79068 0.463789C4.56618 0.241993 5.39476 0.600437 5.72687 1.30139L6.23956 2.38349C6.52263 2.98096 6.37346 3.68312 5.86854 4.12987L4.97297 4.92227C4.9619 4.93206 4.95281 4.9437 4.94616 4.9566C4.85249 5.13827 4.99443 5.62364 5.44074 6.35711C5.94377 7.1838 6.33258 7.51094 6.51215 7.46015L7.68779 7.11912C8.34783 6.92765 9.06312 7.15597 9.46697 7.68704L10.1951 8.64453C10.6678 9.26613 10.5828 10.1237 9.99623 10.6508L9.37001 11.2135C8.92768 11.6109 8.3083 11.7778 7.71184 11.6601C5.96671 11.3159 4.40316 9.98244 3.00808 7.68974C1.61163 5.39478 1.17686 3.44166 1.73773 1.83467C1.92823 1.28887 2.3869 0.865271 2.96708 0.69934ZM3.18187 1.37548C2.83377 1.47503 2.55856 1.72919 2.44427 2.05667C1.96099 3.44133 2.35245 5.1999 3.65264 7.33664C4.95158 9.47135 6.35951 10.6721 7.86334 10.9687C8.22121 11.0393 8.59284 10.9392 8.85824 10.7007L9.48446 10.138C9.8003 9.8542 9.84607 9.39244 9.59154 9.05774L8.86341 8.10025C8.64595 7.81429 8.2608 7.69135 7.90539 7.79445L6.72726 8.1362C6.0752 8.32063 5.46234 7.80498 4.79618 6.7102C4.23223 5.7834 4.03646 5.11396 4.27761 4.64627C4.32421 4.55589 4.38786 4.47437 4.4654 4.40578L5.36095 3.6134C5.63283 3.37284 5.71315 2.99475 5.56073 2.67304L5.04804 1.59094C4.86921 1.2135 4.42305 1.0205 4.00547 1.13993L3.18187 1.37548Z"
                  fill="#9A9A9A"
                ></path>
              </svg>
              <span class="delivery-contact-text">{formatPhone(phoneNumber)}</span>
            </span>
          {/if}
          {#if displayEmail}
            <span
              class="delivery-contact delivery-contact--email"
              title={displayEmail}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="11"
                height="11"
                viewBox="0 0 14 11"
                fill="none"
              >
                <path
                  fill-rule="evenodd"
                  clip-rule="evenodd"
                  d="M0.615885 0.609375L0.0742188 1.16493V10.0538L0.615885 10.6094H12.5326L13.0742 10.0538V1.16493L12.5326 0.609375H0.615885ZM1.15755 2.42086V9.49826H11.9909V2.42067L6.57415 7.4713L1.15755 2.42086ZM11.1314 1.72049H2.0169L6.57415 5.96967L11.1314 1.72049Z"
                  fill="#9A9A9A"
                ></path>
              </svg>
              <span class="delivery-contact-text">{displayEmail}</span>
            </span>
          {/if}
        </div>
      {/if}
    </Card>
  {:else}
    <div class="delivery-summary-bar delivery-summary-bar--empty">
      <div class="summary-left">
        <div class="summary-icon" aria-hidden="true">
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="#404040"
            stroke-width="1.5"
          >
            <path
              d="M12 21s-8-4.438-8-11a8 8 0 0 1 16 0c0 6.562-8 11-8 11z"
              stroke-linecap="round"
              stroke-linejoin="round"
            ></path>
            <circle cx="12" cy="10" r="3"></circle>
          </svg>
        </div>
        <div class="summary-text">
          <div class="summary-top">
            <span class="summary-title">{T("delivery_summary_title")}</span>
          </div>
          <div class="summary-bottom">
            <span class="summary-line">{T("delivery_no_address")}</span>
          </div>
        </div>
      </div>
      <button
        type="button"
        class="edit-button hover:opacity-80"
        on:click={(e) => {
          e.preventDefault();
          e.stopPropagation();
          handleEdit();
        }}
      >
        <span class="edit-text">{T("delivery_add")}</span>
      </button>
    </div>
  {/if}

  {#if showShippingMethod && availableShippingRates.length > 0}
    {@const selectedPrice = (() => {
      const raw = selectedShippingRate?.price || 0;
      return typeof raw === "number" ? raw : parseFloat(raw) || 0;
    })()}
    <div class="shipping-card ">
      <div class="shipping-summary-bar">
        <span class="shipping-card-title">{T("shipping_method_title")}</span>
        <div class="shipping-summary-detail">
          <span class="shipping-summary-name">
            {selectedShippingRate?.title || "Shipping"}
          </span>
          <span class="shipping-summary-dot">·</span>
          <span
            class="shipping-summary-price"
            class:shipping-summary-price--free={selectedPrice === 0}
          >
            {selectedPrice === 0 ? "Free" : formatShippingPrice(selectedPrice) || "Free"}
          </span>
          {#if hasMultipleShippingRates}
            <button
              type="button"
              class="shipping-change-btn hover:opacity-80"
              on:click|stopPropagation={() => (shippingPickerOpen = true)}
            >
              {T("delivery_change")}
            </button>
          {/if}
        </div>
      </div>
    </div>

  {/if}
</div>

{#if showShippingMethod && hasMultipleShippingRates}
  <BottomSlider
    open={shippingPickerOpen}
    title={T("shipping_method_title")}
    height="auto"
    on:close={() => (shippingPickerOpen = false)}
  >
    <div class="shipping-picker-list">
      {#each availableShippingRates as rate, i}
        {@const ratePrice = typeof rate.price === "number" ? rate.price : parseFloat(rate.price) || 0}
        {@const isSelected = selectedShippingHandle === rate.handle}
        {#if i > 0}<div class="shipping-list-divider"></div>{/if}
        <button
          type="button"
          class="shipping-list-row transition-colors duration-200 hover:bg-gray-50"
          class:shipping-list-row--selected={isSelected}
          on:click={() => selectShipping(rate.handle)}
          aria-pressed={isSelected}
        >
          <div class="shipping-radio" aria-hidden="true">
            <input
              type="radio"
              name="shipping-method-picker"
              checked={isSelected}
              tabindex="-1"
              class="sr-only"
            />
            <div class="shipping-radio-outer" class:checked={isSelected}>
              {#if isSelected}<div class="shipping-radio-inner"></div>{/if}
            </div>
          </div>
          <span class="shipping-row-title">{rate.title || "Shipping"}</span>
          <span class="shipping-row-price" class:shipping-row-price--free={ratePrice === 0}>
            {ratePrice === 0 ? "Free" : formatShippingPrice(ratePrice) || "Free"}
          </span>
        </button>
      {/each}
    </div>
  </BottomSlider>
{/if}

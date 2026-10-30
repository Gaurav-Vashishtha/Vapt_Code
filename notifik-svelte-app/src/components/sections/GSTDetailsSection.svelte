<script>
  /**
   * GSTDetailsSection - Displays GST details section (optional)
   * @component
   */
  import { get } from "svelte/store";
  import { appStore } from "../../stores/buttonManager.js";
  import "../../styles/components/sections/DeliveryDetailsSection.css";

  $: settings = $appStore.settings;
  $: gstTitle =
    settings?.gstSectionTitle ||
    settings?.gst_section_title ||
    settings?.gstTitle ||
    settings?.gst_title ||
    "GST Details";
  $: optionalLabel =
    settings?.gstOptionalLabel ||
    settings?.gst_optional_label ||
    settings?.gstOptionalText ||
    settings?.gst_optional_text ||
    "(Optional)";

  // Check if GST section should be clickable/editable
  $: isEditable =
    settings?.gstSectionEditable !== false &&
    settings?.gst_section_editable !== false;

  export let onEdit = () => {};
</script>

<div class="delivery-details-section">
  <div class="section-header">
    <div class="section-title-row">
      {#if settings?.gstSectionIcon !== false && settings?.gst_section_icon !== false}
        <svg
          class="location-icon"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="#404040"
          stroke-width="1.5"
        >
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"
          ></path>
          <polyline points="14 2 14 8 20 8"></polyline>
          <line x1="16" y1="13" x2="8" y2="13"></line>
          <line x1="16" y1="17" x2="8" y2="17"></line>
          <polyline points="10 9 9 9 8 9"></polyline>
        </svg>
      {/if}
      <div class="section-title">
        <span>{gstTitle} </span>
        {#if optionalLabel}
          <span style="color: #979797; font-weight: 400;">{optionalLabel}</span>
        {/if}
      </div>
    </div>
    {#if isEditable}
      <button
        class="edit-button"
        on:click={onEdit}
        aria-label="Add GST Details"
      >
        <svg
          class="edit-icon"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="#404040"
          stroke-width="1.5"
        >
          <line x1="12" y1="5" x2="12" y2="19"></line>
          <line x1="5" y1="12" x2="19" y2="12"></line>
        </svg>
      </button>
    {/if}
  </div>
</div>

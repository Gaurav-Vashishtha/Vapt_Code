<script>
  import { createEventDispatcher, onDestroy } from "svelte";
  import { settingsStore } from "../stores/settingsStore.js";
  import { appStore } from "../stores/buttonManager.js";
  import { fetchZipDetails } from "../services/api.js";
  import { isIndianPhoneNumber } from "../utils/helpers.js";
  import { getCodFormConfig, validateGstField } from "../utils/codFormConfig.js";
  import { createTranslator, getUiCustomization } from "../utils/uiCustomization.js";
  import { addCartAttributesWithOtpStore } from "../utilities/otpUtils.js";
  import { executePost } from "../services/otpService.js";
  import "../styles/components/AddressForm.css";
  import "../styles/components/AddressForm.mobile.css";
export let mode = "add"; // 'add' | 'edit'
export let address = {};
export let email = "";
export let loading = false;
export let phoneFallback = "";
// When true, email is required (controlled by settings flag, e.g. pre_email_mandatory)
export let emailMandatory = false;
// When true, show phone number input field (for COD form without pre-order OTP)
export let showPhoneField = false;

  const dispatch = createEventDispatcher();

  $: safeAddress = address || {};

  let firstName = "";
  let lastName = "";
  let zip = "";
  let city = "";
  let state = "";
  let address1 = "";
  let address2 = "";
  let landmark = "";
  let formEmail = "";
  let addressType = "home";
  let phone = "";
  let company = "";
  let showLandmark = false;
  let stateLocked = false;

  // Merchant COD-form config: custom placeholders + optional GST field.
  // Reactive, not captured: `const` reads the store once at mount, which froze
  // every label and placeholder on this form at whatever was stored then.
  $: codFormConfig = getCodFormConfig($settingsStore);
  $: placeholders = codFormConfig.placeholders;

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore);
  $: uiTexts = getUiCustomization($settingsStore).texts || {};
  // Field labels: ui_customization wins, then the cod_form_config label, then default
  $: L = (key, cfgKey) =>
    uiTexts[key] || (cfgKey ? codFormConfig.labels[cfgKey] : "") || T(key);
  $: gstConfig = codFormConfig.gst;
  let gst = "";

  // Pincode handling is India-specific (6-digit + zip auto-lookup). Non-Indian
  // users fill the postal code manually with no format validation or lookup.
  // The stored number is the bare national one, so ten Indian digits alone do
  // not identify India: the calling code has to come with it, the way
  // AddressSelection already passes it. Without this an Indian customer got
  // the postal code field and no pincode lookup.
  $: isIndianUser = isIndianPhoneNumber(
    phoneFallback || phone,
    $appStore?.countryCallingCode,
  );

  let errors = {};
  let touched = {};
  let submitted = false;
  let emailTouched = false;
  let loadingPincode = false;

  // Debounce timer for zip code fetch
  let zipFetchTimeout = null;

  const emailRegex = /^[\w-.]+@([\w-]+\.)+[\w-]{2,}$/i;
  // Reactive, so these follow a copy change like every other label here.
  $: addressTypeOptions = [
    { value: "home", label: T("addr_type_home") },
    { value: "office", label: T("addr_type_office") },
    { value: "other", label: T("addr_type_other") },
  ];

  function initializeForm() {
    firstName = safeAddress.first_name || "";
    lastName = safeAddress.last_name || "";
    zip = safeAddress.zip || "";
    city = safeAddress.city || "";
    state = safeAddress.province || safeAddress.state || "";
    stateLocked = !!state.trim();
    address1 = safeAddress.address1 || "";
    address2 = safeAddress.address2 || "";
    landmark = safeAddress.landmark || "";
    showLandmark = !!landmark.trim();
    formEmail = email || safeAddress.email || "";
    emailTouched = false;
    addressType = safeAddress.address_type || "home";
    phone = safeAddress.phone || phoneFallback || "";
    company = safeAddress.company || "";
    errors = {};
    touched = {};
    submitted = false;
  }

  let previousAddressRef = null;
  let previousMode = null;

  $: if (address !== previousAddressRef || mode !== previousMode) {
    initializeForm();
    previousAddressRef = address;
    previousMode = mode;
  }

  let lastEmailProp = "";
  $: if (!emailTouched) {
    const incomingEmail = email || safeAddress.email || "";
    if (incomingEmail !== lastEmailProp) {
      formEmail = incomingEmail;
      lastEmailProp = incomingEmail;
    }
  }

  const validators = {
    zip(value) {
      const trimmed = value.trim();
      if (!trimmed) return isIndianUser ? "Pincode is required" : "Postal code is required";
      // Only Indian addresses use the strict 6-digit pincode format.
      if (isIndianUser && !/^\d{6}$/.test(trimmed)) return "Enter a valid pincode";
      return "";
    },
    city(value) {
      return value.trim() ? "" : "City can't be empty";
    },
    state(value) {
      return value.trim() ? "" : "Select your state";
    },
    address1(value) {
      return value.trim() ? "" : "Flat/House No. is required";
    },
    address2(value) {
      return value.trim() ? "" : "Apartment details are required";
    },
    firstName(value) {
      return value.trim() ? "" : "First name is required";
    },
    formEmail(value) {
      const trimmed = value.trim();
      if (!trimmed) {
        return emailMandatory ? "Email is required" : "";
      }
      if (!emailRegex.test(trimmed)) return "Enter a valid email address";
      return "";
    },
    formPhone(value) {
      if (!showPhoneField) return "";
      const trimmed = value.trim().replace(/\D/g, "");
      if (!trimmed) return "Phone number is required";
      if (trimmed.length < 10) return "Enter a valid 10-digit phone number";
      return "";
    },
    gst(value) {
      if (!gstConfig.enabled) return "";
      return validateGstField(value, { required: gstConfig.required });
    },
  };

  const fieldMap = {
    zip: () => zip,
    city: () => city,
    state: () => state,
    address1: () => address1,
    address2: () => address2,
    firstName: () => firstName,
    formEmail: () => formEmail,
    formPhone: () => phone,
    gst: () => gst,
  };

  function runValidation(field) {
    const validator = validators[field];
    if (!validator) return "";
    return validator(fieldMap[field] ? fieldMap[field]() : "");
  }

  function setFieldError(field, message) {
    // ⚡ CRITICAL: Create new object to ensure Svelte reactivity detects the change
    const nextErrors = { ...errors };
    if (message) {
      nextErrors[field] = message;
    } else {
      delete nextErrors[field];
    }
    // ⚡ CRITICAL: Assign new object to trigger reactivity
    errors = nextErrors;
  }

  function validateField(field) {
    const message = runValidation(field);
    setFieldError(field, message);
    return !message;
  }

  function validateAll() {
    let isValid = true;
    // ⚡ CRITICAL: Mark all fields as touched when validating on submit
    // This ensures validation errors are visible even when form is submitted programmatically
    // Create completely new objects to ensure Svelte reactivity detects the changes
    const newTouched = {};
    const newErrors = {};

    // Mark all fields as touched and validate them
    Object.keys(validators).forEach((field) => {
      newTouched[field] = true; // Mark as touched
      const result = runValidation(field);
      if (result) {
        newErrors[field] = result;
        isValid = false;
      }
    });

    // ⚡ CRITICAL: Update both touched and errors atomically to trigger reactivity
    // This ensures the template re-renders and shows validation errors
    // Use Object.assign to create completely new objects that Svelte will detect
    touched = Object.assign({}, newTouched);
    errors = Object.assign({}, newErrors);

    return isValid;
  }

  function markTouched(field) {
    // ⚡ CRITICAL: Create new object to ensure Svelte reactivity detects the change
    touched = { ...touched, [field]: true };
  }

  $: shouldShowError = (field) =>
    !!errors[field] && (!!touched[field] || !!submitted);

  function handlePincodeInput(event) {
    // Non-Indian: free-form postal code (letters/length allowed), no auto-lookup.
    if (!isIndianUser) {
      zip = event.target.value;
      return;
    }

    const value = event.target.value.replace(/\D/g, "").slice(0, 6);
    zip = value;

    // ⚡ CRITICAL: Auto-fetch state and city when pincode reaches 6 digits
    // Works in both "add" and "edit" modes - if user changes pincode, update city/state
    if (value.length === 6) {
      // Clear any existing timeout
      if (zipFetchTimeout) {
        clearTimeout(zipFetchTimeout);
      }

      // Debounce the API call (500ms delay)
      zipFetchTimeout = setTimeout(async () => {
        await fetchZipDetailsFromAPI(value);
      }, 500);
    }
  }

  async function fetchZipDetailsFromAPI(pincode) {
    // Zip auto-lookup is India-only (backend zip_details expects IN pincodes).
    if (!isIndianUser) return;
    if (!pincode || pincode.length !== 6) {
      return;
    }

    loadingPincode = true;

    try {
      const zipDetails = await fetchZipDetails({
        zip: pincode,
        country_code: "IN",
      });

      const locationData = zipDetails?.location;

      if (locationData) {
        // ⚡ CRITICAL: Only update if location data exists
        // Map backend response to form fields
        if (locationData.city) {
          city = locationData.city;
          // Validate city after setting
          const cityError = runValidation("city");
          setFieldError("city", cityError);
        }

        if (locationData.province) {
          state = locationData.province;
          stateLocked = true;
          // Validate state after setting
          const stateError = runValidation("state");
          setFieldError("state", stateError);
        }
      } else {
        // ⚡ CRITICAL: Don't show error - let user complete form manually
      }
    } catch (_error) {
    } finally {
      loadingPincode = false;
    }
  }

  function handleEmailInput(event) {
    emailTouched = true;
    formEmail = event.target.value;
  }

  function handleSubmit(event) {
    event.preventDefault();

    if (loading) {
      return;
    }

    submitted = true;

    const isValid = validateAll();

    if (!isValid) {
      // ⚡ CRITICAL: Scroll to first error field to make validation errors visible
      // This ensures user sees what needs to be fixed when form is submitted programmatically
      const firstErrorField = Object.keys(errors).find((key) => errors[key]);
      if (firstErrorField) {
        // Try multiple selectors to find the error field
        const errorElement =
          document.querySelector(`[name="${firstErrorField}"]`) ||
          document.querySelector(`#${firstErrorField}`) ||
          document.querySelector(
            `.field-block:has([name="${firstErrorField}"])`,
          );
        if (errorElement) {
          errorElement.scrollIntoView({ behavior: "smooth", block: "center" });
          // Focus the input for better UX
          const input =
            errorElement.querySelector("input") ||
            errorElement.querySelector("select");
          if (input) {
            setTimeout(() => input.focus(), 100);
          }
        }
      }
      return;
    }

    const saveData = {
      firstName: firstName.trim(),
      lastName: lastName.trim() || firstName.trim(),
      phone: phone.trim(),
      email: formEmail.trim(),
      address1: address1.trim(),
      address2: address2.trim(),
      city: city.trim(),
      state: state.trim(),
      zip: zip.trim(),
      company: company.trim(),
      addressType,
      landmark: landmark.trim(),
    };

    // GST is stored as a cart attribute keyed by the merchant's label, not on the address.
    if (gstConfig.enabled && gst.trim()) {
      const gstAttrs = { [gstConfig.label]: gst.trim().toUpperCase() };
      try {
        executePost({ attributes: gstAttrs });
      } catch (_) {}
      addCartAttributesWithOtpStore(gstAttrs);
    }

    dispatch("save", saveData);
  }

  // Cleanup: Clear timeout on component destroy
  onDestroy(() => {
    if (zipFetchTimeout) {
      clearTimeout(zipFetchTimeout);
      zipFetchTimeout = null;
    }
  });
</script>

<form class="billing af-form" novalidate on:submit|preventDefault={handleSubmit}>
  <div class="af-field" class:has-error={shouldShowError("zip")}>
    <input
      id="pincode"
      class="af-input"
      type="text"
      inputmode={isIndianUser ? "numeric" : "text"}
      autocomplete="postal-code"
      maxlength={isIndianUser ? 6 : 16}
      placeholder={isIndianUser ? "6-digit pincode" : " "}
      value={zip}
      on:input={handlePincodeInput}
      on:blur={() => {
        markTouched("zip");
        validateField("zip");
      }}
    />
    <label class="af-label" for="pincode">
      {isIndianUser ? L("addr_pincode", "pincode") : T("addr_postal_code")} <span class="af-asterisk">*</span>
    </label>
    {#if loadingPincode}
      <p class="af-helper">{T("addr_validating_pincode")}</p>
    {/if}
    {#if shouldShowError("zip")}
      <p class="af-error">{errors.zip}</p>
    {/if}
  </div>

  <div class="af-row">
    <div class="af-field" class:has-error={shouldShowError("firstName")}>
      <input
        id="firstName"
        class="af-input"
        type="text"
        autocomplete="given-name"
        maxlength="60"
        placeholder=" "
        bind:value={firstName}
        on:blur={() => {
          markTouched("firstName");
          validateField("firstName");
        }}
      />
      <label class="af-label" for="firstName">
        {L("addr_first_name", "name")} <span class="af-asterisk">*</span>
      </label>
      {#if shouldShowError("firstName")}
        <p class="af-error">{errors.firstName}</p>
      {/if}
    </div>

    <div class="af-field">
      <input
        id="lastName"
        class="af-input"
        type="text"
        autocomplete="family-name"
        maxlength="60"
        placeholder=" "
        bind:value={lastName}
      />
      <label class="af-label" for="lastName">
        {T("addr_last_name")} <span class="af-asterisk">*</span>
      </label>
    </div>
  </div>

  <div class="af-field" class:has-error={shouldShowError("address1")}>
    <textarea
      id="line1"
      class="af-input af-textarea"
      autocomplete="address-line1"
      maxlength="255"
      rows="2"
      placeholder=" "
      bind:value={address1}
      on:blur={() => {
        markTouched("address1");
        validateField("address1");
      }}
    ></textarea>
    <label class="af-label" for="line1">
      {L("addr_line1", "address1")} <span class="af-asterisk">*</span>
    </label>
    {#if shouldShowError("address1")}
      <p class="af-error">{errors.address1}</p>
    {/if}
  </div>

  <div class="af-field" class:has-error={shouldShowError("address2")}>
    <textarea
      id="line2"
      class="af-input af-textarea"
      autocomplete="address-line2"
      maxlength="170"
      rows="2"
      placeholder=" "
      bind:value={address2}
      on:blur={() => {
        markTouched("address2");
        validateField("address2");
      }}
    ></textarea>
    <label class="af-label" for="line2">
      {L("addr_line2", "address2")} <span class="af-asterisk">*</span>
    </label>
    {#if shouldShowError("address2")}
      <p class="af-error">{errors.address2}</p>
    {/if}
  </div>

  {#if showLandmark}
    <div class="af-field">
      <input
        id="landmark"
        class="af-input"
        type="text"
        maxlength="50"
        placeholder=" "
        bind:value={landmark}
      />
      <label class="af-label" for="landmark">{T("addr_landmark")}</label>
    </div>
  {/if}

  <!-- <div class="af-field" class:has-error={shouldShowError("formPhone")}>
    <input
      id="phone"
      class="af-input"
      type="tel"
      autocomplete="tel"
      disabled={!showPhoneField}
      placeholder="10-digit mobile number"
      bind:value={phone}
      on:blur={() => {
        markTouched("formPhone");
        validateField("formPhone");
      }}
    />
    <label
      class="af-label"
      class:af-label--disabled={!showPhoneField}
      for="phone"
    >
      Receiver’s number <span class="af-asterisk">*</span>
    </label>
    {#if shouldShowError("formPhone")}
      <p class="af-error">{errors.formPhone}</p>
    {/if}
  </div>
  <span class="af-note">We'll contact you on this number during delivery</span> -->

  <div class="af-row">
    <div class="af-field" class:has-error={shouldShowError("city")}>
      <input
        id="city"
        class="af-input"
        type="text"
        autocomplete="address-level2"
        maxlength="100"
        placeholder=" "
        bind:value={city}
        on:blur={() => {
          markTouched("city");
          validateField("city");
        }}
      />
      <label class="af-label" for="city">
        {L("addr_city", "city")} <span class="af-asterisk">*</span>
      </label>
      {#if shouldShowError("city")}
        <p class="af-error">{errors.city}</p>
      {/if}
    </div>

    <div class="af-field" class:has-error={shouldShowError("state")}>
      <input
        id="state"
        class="af-input"
        type="text"
        disabled={stateLocked}
        placeholder=" "
        bind:value={state}
        on:blur={() => {
          markTouched("state");
          validateField("state");
        }}
      />
      <label
        class="af-label"
        class:af-label--disabled={stateLocked}
        for="state"
      >
        {L("addr_state", "state")} <span class="af-asterisk">*</span>
      </label>
      {#if shouldShowError("state")}
        <p class="af-error">{errors.state}</p>
      {/if}
    </div>
  </div>

  <div class="af-field" class:has-error={shouldShowError("formEmail")}>
    <input
      id="email"
      class="af-input"
      type="email"
      autocomplete="email"
      placeholder={placeholders.email}
      value={formEmail}
      on:input={handleEmailInput}
      on:blur={() => {
        markTouched("formEmail");
        validateField("formEmail");
      }}
    />
    <label class="af-label" for="email">
      {L("addr_email", "email")} {#if emailMandatory}<span class="af-asterisk">*</span>{/if}
    </label>
    {#if shouldShowError("formEmail")}
      <p class="af-error">{errors.formEmail}</p>
    {/if}
  </div>
  <span class="af-note">{T("addr_email_note")}</span>

  {#if gstConfig.enabled}
    <div class="af-field" class:has-error={shouldShowError("gst")}>
      <label class="af-label" for="gst">
        {gstConfig.label}{#if gstConfig.required} <span class="af-asterisk">*</span>{/if}
      </label>
      <input
        id="gst"
        class="af-input"
        type="text"
        name="gst"
        maxlength="15"
        placeholder={gstConfig.placeholder}
        bind:value={gst}
        on:blur={() => {
          markTouched("gst");
          validateField("gst");
        }}
      />
      {#if shouldShowError("gst")}
        <p class="af-error">{errors.gst}</p>
      {/if}
    </div>
  {/if}

  <div class="af-type-section">
    <p class="af-type-title">{T("addr_type_title")}</p>
    <div class="af-type-options">
      {#each addressTypeOptions as option}
        <label class="af-type-option">
          <input
            type="radio"
            class="af-type-radio"
            name="addressType"
            value={option.value}
            bind:group={addressType}
          />
          <span
            class="af-type-circle"
            class:checked={addressType === option.value}
          ></span>
          <span class="af-type-label">{option.label}</span>
        </label>
      {/each}
    </div>
  </div>

  <div class="af-submit-bar">
    <button type="submit" class="af-submit" disabled={loading}>
      {#if loading}
        Saving…
      {:else}
        Save and select
      {/if}
    </button>
  </div>
</form>

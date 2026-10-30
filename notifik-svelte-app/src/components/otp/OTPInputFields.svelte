<script>
  import { createEventDispatcher } from "svelte";
  import { onMount } from "svelte";
  import "../../styles/components/otp/OTPInputFields.css";

  export let otpValues = ["", "", "", ""];
  export let activeIndex = 0;
  export let disabled = false;
  export let error = false;

  const dispatch = createEventDispatcher();

  function setInputValue(index, digit) {
    const inputElement = document.getElementById(`otp-input-${index}`);
    if (inputElement && inputElement instanceof HTMLInputElement) {
      inputElement.value = digit;
    }
  }

  function handleInput(index, event) {
    if (!(event.target instanceof HTMLInputElement)) return;
    let rawValue = event.target.value || "";
    rawValue = rawValue.replace(/\D/g, "");

    const newValues = [...otpValues];

    if (rawValue.length <= 1) {
      newValues[index] = rawValue;
      otpValues = newValues;
      dispatch("otpChange", { values: otpValues, index });

      if (rawValue && index < otpValues.length - 1) {
        focusInput(index + 1);
      }
      return;
    }

    let cursor = index;
    rawValue.split("").forEach((digit) => {
      if (cursor < newValues.length) {
        newValues[cursor] = digit;
        setInputValue(cursor, digit);
        cursor += 1;
      }
    });

    otpValues = newValues;
    dispatch("otpChange", { values: otpValues, index });

    if (cursor <= otpValues.length - 1) {
      focusInput(cursor);
    } else {
      focusInput(otpValues.length - 1);
    }
  }

  function handleKeyDown(index, event) {
    if (event.key === "Backspace") {
      event.preventDefault();
      const newValues = [...otpValues];
      if (newValues[index]) {
        newValues[index] = "";
        otpValues = newValues;
        dispatch("otpChange", { values: otpValues, index });
      } else if (index > 0) {
        focusInput(index - 1);
      }
      return;
    }

    if (event.key === "ArrowLeft" && index > 0) {
      event.preventDefault();
      focusInput(index - 1);
      return;
    }

    if (event.key === "ArrowRight" && index < otpValues.length - 1) {
      event.preventDefault();
      focusInput(index + 1);
      return;
    }

    if (event.key === "Enter") {
      dispatch("submit");
    }
  }

  onMount(() => {
    focusInput(activeIndex || 0);
  });

  function handlePaste(event) {
    event.preventDefault();
    const pasted = (event.clipboardData?.getData("text") || "")
      .replace(/\D/g, "")
      .slice(0, 4);

    if (!pasted) return;

    const newValues = [...otpValues];
    for (let i = 0; i < otpValues.length; i += 1) {
      newValues[i] = pasted[i] || "";
      setInputValue(i, newValues[i]);
    }
    otpValues = newValues;
    dispatch("otpChange", { values: otpValues });

    const firstEmptyIndex = otpValues.findIndex((digit) => !digit);
    if (firstEmptyIndex === -1) {
      focusInput(otpValues.length - 1);
    } else {
      focusInput(firstEmptyIndex);
    }
  }

  function focusInput(index) {
    setTimeout(() => {
      const inputElement = document.getElementById(`otp-input-${index}`);
      if (inputElement && inputElement instanceof HTMLInputElement) {
        inputElement.focus();
        inputElement.select();
      }
      activeIndex = index;
      dispatch("focusChange", { index });
    }, 0);
  }

  function handleBoxClick(index) {
    if (!disabled) {
      focusInput(index);
    }
  }
</script>

<div class="otp-input-container">
  {#each otpValues as value, index}
    <div
      class="otp-input-wrapper"
      role="presentation"
      on:click={() => handleBoxClick(index)}
    >
      <div
        class="otp-box"
        class:active={activeIndex === index && !disabled}
        class:filled={!!value}
        class:error
      >
        <input
          type="text"
          id="otp-input-{index}"
          class="otp-input-visible"
          maxlength={index === 0 ? 4 : 1}
          inputmode="numeric"
          pattern="[0-9]*"
          autocomplete={index === 0 ? "one-time-code" : "off"}
          name={index === 0 ? "otp" : `otp-digit-${index}`}
          aria-label={`OTP digit ${index + 1}`}
          enterkeyhint={index === otpValues.length - 1 ? "done" : "next"}
          {value}
          {disabled}
          on:input={(e) => handleInput(index, e)}
          on:keydown={(e) => handleKeyDown(index, e)}
          on:paste={handlePaste}
          on:focus={() => {
            activeIndex = index;
            dispatch("focusChange", { index });
          }}
        />
      </div>
    </div>
  {/each}
</div>

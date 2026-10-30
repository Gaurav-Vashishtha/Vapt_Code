import React, { useState, useEffect } from "react";
import PhoneInput from "react-phone-input-2";
import "react-phone-input-2/lib/material.css";
import {
  debugLog,
  getSessionValue,
  PHONE_PLACE_HOLDER,
  validatePhoneNumber,
} from "../utilities/otpUtils";
import { useAppContext } from "../context/AppContext";
import useOtpStore from "../stores/otpStore";
import CountryCode from "../../Components/CountryCode";
export default function PhoneInputBox({ handlePhoneSubmitSms }) {
  // const { phone, valid, countries, setSelectedCountry, setPhone, setValid } =
  //   useAppContext();
  const { otpData, setOtpData } = useOtpStore();
  const { phoneNumber } = otpData;
  const settings = getSessionValue("settingSession");
  const { isNewDesignEnabled } = settings;
  const countryArray = getSessionValue("countryArray");
  const [selectedCountry, setSelectedCountry] = useState(countryArray[0]);
  const handleChange = (value, country) => {
    debugLog("phone", value);

    // setSelectedCountry(country);
    // setPhone(value);

    setOtpData({
      phoneNumber: value,
      countryCode: country?.countryCode?.toUpperCase(),
    });
    setSelectedCountry(country?.countryCode.toLowerCase());
    // setValid(validatePhoneNumber(value));

    if (value.length > 9) {
      setOtpData({ isValidNumber: true });
    } else {
      debugLog("not valid number", value.length);
      setOtpData({ isValidNumber: false });
    }
  };

  return (
    <>
      <style>
        {`
      .react-tel-input {
        z-index: 100000 !important;
        position: relative !important;
        font-family: "Tasa", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif !important;
      }

      .react-tel-input .selected-flag .arrow {
        display: block !important;
      }

      .react-tel-input .special-label {
        background: #fafafa !important;
        font-family: "Tasa", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif !important;
      }
    `}
      </style>
      <PhoneInput
        country={countryArray[0]}
        value={phoneNumber}
        onChange={handleChange}
        onlyCountries={countryArray || ["in"]}
        countryCodeEditable={false}
        enableSearch={true}
        autoFormat={false}
        autocompleteSearch={false}
        specialLabel={PHONE_PLACE_HOLDER}
        onEnterKeyPress={() => handlePhoneSubmitSms()}
        enableLongNumbers={selectedCountry === "pk"} // Conditionally enable long numbers only if the selected country is "pk"
        searchPlaceholder="Search countries..."
        inputStyle={{ zIndex: 999999 }}
        inputProps={
          isNewDesignEnabled == false
            ? {
                required: true,
                autoFocus: true,
                style: {
                  width: "100%",
                  height: "60px",
                  fontSize: "16px",
                  borderRadius: "4px",
                  border: "1px solid #d1d5db",
                  paddingLeft: "15%",
                },
              }
            : {
                required: true,
                autoFocus: false,
                name: "phone", // Ensures it's not considered a password field
                id: "phone-number-input",
                type: "tel", // Use 'tel' instead of 'number' to signal it's not a password
                inputMode: "numeric", // Ensures only numeric keyboard appears on mobile
                pattern: "[0-9]*", // Restricts input to only digits
                autoComplete: "new-password", // Forces browser to NOT use saved passwords
                autoCorrect: "off",
                spellCheck: "false",

                style: {
                  width: "100%",
                  height: "52px",
                  fontSize: "15px", // Adjusted for better readability
                  lineHeight: "17px",
                  fontFamily: "'Tasa', sans-serif",
                  borderRadius: "8px", // Increased for smoother look
                  border: "1px solid #d1d5db", // Maintained professional light gray border
                  fontWeight: "500", // Added for better text visibility
                  transition:
                    "border-color 0.3s ease-in-out, box-shadow 0.3s ease-in-out",
                  zIndex: "99999",
                  backgroundColor: "white", // Ensuring a clean, modern background
                  color: "#333", // Dark gray text for readability
                  outline: "none", // Removes default focus outline
                  cursor: "default",
                },

                onFocus: (e) => {
                  e.target.style.borderColor = "black"; // Match button theme
                  e.target.style.boxShadow = "0px 4px 8px rgba(0, 0, 0, 0.1)"; // Soft focus glow
                },

                onBlur: (e) => {
                  e.target.style.borderColor = "#d1d5db"; // Reset to original light gray
                  e.target.style.boxShadow = "none"; // Remove glow when not focused
                },
              }
        }
        containerStyle={{
          width: "100%",
        }}
        dropdownStyle={{
          width: "250px",
          paddingLeft: "5%",
          paddingRight: "5%",
        }}
        buttonStyle={{
          border: "none",
          background: "none",
        }}
      />
    </>
  );
}

// inputProps={{
//   required: true,
//   name: "phone", // Ensures it's not considered a password field
//   id: "phone-number-input",
//   type: "tel", // Use 'tel' instead of 'number' to signal it's not a password
//   inputMode: "numeric", // Ensures only numeric keyboard appears on mobile
//   pattern: "[0-9]*", // Restricts input to only digits
//   autoComplete: "new-password", // Forces browser to NOT use saved passwords
//   autoCorrect: "off",
//   spellCheck: "false",

//   style: {
//     width: "100%",
//     height: "43px",
//     fontSize: "15px", // Adjusted for better readability
//     lineHeight: "17px",
//     borderRadius: "8px", // Increased for smoother look
//     border: "1px solid #d1d5db", // Maintained professional light gray border
//     fontWeight: "500", // Added for better text visibility
//     transition:
//       "border-color 0.3s ease-in-out, box-shadow 0.3s ease-in-out",
//     backgroundColor: "white", // Ensuring a clean, modern background
//     color: "#333", // Dark gray text for readability
//     outline: "none", // Removes default focus outline
//   },

//   onFocus: (e) => {
//     e.target.style.borderColor = "black"; // Match button theme
//     e.target.style.boxShadow = "0px 4px 8px rgba(0, 0, 0, 0.1)"; // Soft focus glow
//   },

//   onBlur: (e) => {
//     e.target.style.borderColor = "#d1d5db"; // Reset to original light gray
//     e.target.style.boxShadow = "none"; // Remove glow when not focused
//   },
// }}

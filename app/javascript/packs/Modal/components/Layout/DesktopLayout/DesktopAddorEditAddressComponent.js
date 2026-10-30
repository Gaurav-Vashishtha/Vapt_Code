import React, { useEffect, useState } from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
import {
  buildBuyerIdentityPayload,
  debugLog,
  getCurrentStep,
  getSessionValue,
  setSessionValue,
  getStorefrontCartId,
  getCodFormConfig,
  addCartAttributesWithOtpStore,
} from "../../../utilities/otpUtils";
import { updateBuyerIdentity } from "../../../services/cartService";
import {
  fetchZipDetails,
  getCart,
  updateShippingAddresses,
} from "../../../services/otpService";
import {
  validateAddressField,
  validateAddressForm,
  validateGstField,
  normalizeProvince,
  splitFullName,
} from "../../../utilities/addressValidation";

import { ArrowLeft, Loader } from "lucide-react";

import debounce from "lodash.debounce";

const AddressFormContainerCODK = styled.div`
  width: 100% !important;
  max-width: 480px !important; /* Reduced from 520px */
  margin: 20px auto !important; /* Reduced from 32px */
  background: #ffffff !important;
  border-radius: 10px !important; /* Reduced from 12px */
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.1) !important; /* Adjusted shadow */
  padding: 20px !important; /* Reduced from 32px */
  display: flex !important;
  flex-direction: column !important;
  max-height: 70vh !important;
  overflow-y: auto !important;
`;

const TitleCODK = styled.div`
  font-size: 16px !important; /* Reduced from 18px */
  line-height: 22px !important; /* Reduced from 24px */
  font-weight: bold !important;
  color: #1f1f1f !important;
`;

const FormCODK = styled.form`
  display: flex !important;
  flex-direction: column !important;
  gap: 15px !important; /* Reduced from 20px */
`;

const FormGroupCODK = styled.div`
  display: flex !important;
  flex-direction: column !important;
  gap: 3px !important; /* Reduced from 4px */
`;

const ErrorTextCODK = styled.div`
  color: #dc2626 !important;
  font-size: 12px !important; /* Reduced from 13px */
  margin-top: 3px !important; /* Reduced from 4px */
`;

const RowCODK = styled.div`
  display: flex !important;
  gap: 12px !important; /* Reduced from 16px */
`;

const ButtonCODK = styled.button`
  width: 100% !important;
  min-width: 140px !important; /* Reduced from 160px */
  padding: 10px 20px !important; /* Reduced from 12px 24px */
  background-color: ${(props) =>
    props.bgColor || props.theme.primary} !important;
  color: ${(props) => props.textColor || props.theme.secondary} !important;
  border: none !important;
  border-radius: 8px !important; /* Reduced from 10px */
  font-size: 13px !important; /* Reduced from 14px */
  font-weight: 600 !important;
  cursor: pointer !important;
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  gap: 6px !important; /* Reduced from 8px */
  transition: background-color 0.3s ease-in-out, box-shadow 0.3s,
    transform 0.2s ease-in-out !important;
  box-shadow: 0px 3px 5px rgba(0, 0, 0, 0.1) !important; /* Adjusted shadow */

  &:hover {
    background-color: ${(props) =>
      props.hoverBgColor || props.theme.primaryDark} !important;
    box-shadow: 0px 5px 10px rgba(0, 0, 0, 0.2) !important;
  }

  &:active {
    transform: scale(0.97) !important;
    box-shadow: inset 0px 2px 5px rgba(0, 0, 0, 0.2) !important;
  }

  &:disabled {
    background-color: ${(props) =>
      props.disabledBgColor || props.theme.border} !important;
    color: ${(props) => props.disabledTextColor || props.theme.text} !important;
    cursor: not-allowed !important;
    box-shadow: none !important;
  }
`;

const InputCODK = styled.input`
  width: 100% !important;
  padding: 12px 14px !important;
  border: 1px solid
    ${({ hasError, theme }) =>
      hasError ? "#e53935" : theme.border || "#D9DEE3"} !important;
  border-radius: 6px !important;
  font-size: 13px !important;
  color: ${(props) => props.theme.text || "#1E1E1E"} !important;
  background: ${(props) => props.theme.inputBg || "#FFFFFF"} !important;
  transition: border-color 0.2s ease, box-shadow 0.2s ease !important;

  &::placeholder {
    color: ${(props) => props.theme.placeholder || "#9CA3AF"} !important;
    font-size: 11px !important;
  }

  &:focus {
    outline: none !important;
    border-color: ${({ hasError, theme }) =>
      hasError ? "#e53935" : theme.primary || "rgb(218, 118, 141)"} !important;
    box-shadow: ${({ hasError }) =>
      hasError
        ? "0 0 0 2px rgba(229, 57, 53, 0.2)"
        : "0 0 0 2px rgba(218, 118, 141, 0.2)"} !important;
  }

  &:disabled {
    background-color: ${(props) =>
      props.theme.disabledBg || "#F3F4F6"} !important;
    color: ${(props) => props.theme.disabledText || "#9CA3AF"} !important;
    cursor: not-allowed !important;
  }
`;

const TitleSubtle = styled.div`
  font-size: 13px !important; /* Reduced from 14px */
  font-weight: 600 !important;
  color: #4b5563 !important;
  margin-top: 6px !important; /* Reduced from 8px */
  margin-bottom: 3px !important; /* Reduced from 4px */
`;

const TextAreaCODK = styled.textarea`
  width: 100% !important;
  height: 50px !important; /* Reduced from 60px */
  padding: 12px 14px !important; /* Reduced from 14px 16px */
  border: 1px solid ${(props) => props.theme.border || "#e5e7eb"} !important;
  border-radius: 6px !important; /* Reduced from 8px */
  font-size: 13px !important; /* Reduced from 14px */
  color: ${(props) => props.theme.textDark || "#1f2937"} !important;
  background: ${(props) => props.theme.inputBg || "#f9fafb"} !important;
  transition: border-color 0.2s ease !important;
  resize: vertical;

  &::placeholder {
    color: ${(props) => props.theme.placeholder || "#9ca3af"} !important;
    font-size: 11px !important;
  }

  &:focus {
    outline: none !important;
    border-color: ${(props) => props.theme.primary || "#4f46e5"} !important;
  }

  &:disabled {
    background-color: ${(props) =>
      props.theme.disabledBg || "#f3f4f6"} !important;
    color: ${(props) => props.theme.disabledText || "#9ca3af"} !important;
    cursor: not-allowed !important;
  }
`;

const BackToAddressesButtonCODK = styled.button`
  display: flex !important;
  align-items: center !important;
  gap: 3px !important; /* Reduced from 4px */
  background: none !important;
  border: none !important;
  font-size: 13.5px !important; /* Reduced from 14.5px */
  font-weight: 600 !important;
  cursor: pointer !important;
  padding: 0 !important;
  margin-bottom: 18px !important; /* Reduced from 24px */
  color: ${(props) =>
    props.theme.link || props.theme.primary || "#4f46e5"} !important;

  &:hover {
    color: ${(props) =>
      props.theme.linkHover || props.theme.primaryDark || "#4338ca"} !important;
  }
`;

const addressTemplate = {
  address1: "",
  address2: "",
  city: "",
  company: null,
  coordinates_validated: null,
  country: "India",
  country_code: "IN",
  country_code_v2: "IN",
  formatted: "",
  formatted_area: "",
  id: null,
  first_name: "",
  last_name: "",
  latitude: null,
  longitude: null,
  phone: "",
  province: "",
  province_code: "",
  zip: "",
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
};

function AddOrEditAddress({ theme }) {
  const {
    editableAddress,
    isEditAddress,
    setStep,
    otpData,
    setOtpData,
    setIsPrefilledAddressCompleted,
    setBuyerIdentity,
    isCartReady,
  } = useOtpStore();
  const settings = getSessionValue("settingSession");
  const codFormConfig = getCodFormConfig(settings);
  const placeholders = codFormConfig.placeholders;
  const labels = codFormConfig.labels;
  const gstConfig = codFormConfig.gst;

  const { isLoading } = otpData;
  const shippingAddresses = getSessionValue("shipping_addresses");
  const [loadingPincode, setLoadingPincode] = useState(false);

  const [formData, setFormData] = useState({
    fullName: "",
    address1: "",
    address2: "",
    pincode: "",
    city: "",
    state: "",
    email: "",
    gst: "",
  });

  const [errors, setErrors] = useState({});

  useEffect(() => {
    const sessionEmail = getSessionValue("customer-email");

    if (isEditAddress && editableAddress) {
      setFormData({
        fullName:
          (editableAddress?.first_name || "") +
          " " +
          (editableAddress?.last_name || ""),
        address1: editableAddress.address1 || "",
        address2: editableAddress.address2 || "",
        pincode: editableAddress.zip || "",
        city: editableAddress.city || "",
        state: editableAddress.province || "",
        email: editableAddress.email || sessionEmail || "",
      });
    } else {
      setFormData((prev) => ({
        ...prev,
        email: sessionEmail || "",
      }));
    }
  }, [isEditAddress, editableAddress]);

  const validateField = (name, value) => validateAddressField(name, value);

  const handleInputChange = (e) => {
    const { name, value } = e.target;

    setFormData((prev) => ({
      ...prev,
      [name]: value,
    }));

    setOtpData((prev) => ({
      ...prev,
      error: null,
    }));

    if (name === "email" && otpData.error === "Email is invalid") {
      setOtpData((prev) => ({
        ...prev,
        error: null,
      }));
    }

    if (name === "pincode" && value.length === 6) {
      debouncedFetchZipDetails(value);
    }

    const fieldError =
      name === "gst"
        ? validateGstField(value, { required: gstConfig.required })
        : validateField(name, value);
    setErrors((prev) => ({
      ...prev,
      [name]: fieldError,
    }));
  };

  const debouncedFetchZipDetails = debounce(async (pincode) => {
    setLoadingPincode(true);
    try {
      const zipDetails = await fetchZipDetails({
        zip: pincode,
        country_code: "IN",
      });
      const locationData = zipDetails.location;
      if (locationData) {
        setFormData((prev) => ({
          ...prev,
          city: locationData.city || "",
          state: locationData.province || "",
        }));
        setErrors((prev) => ({
          ...prev,
          city: validateField("city", locationData.city || ""),
          state: validateField("state", locationData.province || ""),
        }));
      }
    } catch (error) {
      console.error("Error fetching zip details:", error);
    } finally {
      setLoadingPincode(false);
    }
  }, 500);

  const handleFormSubmit = (e) => {
    e.preventDefault();

    const newErrors = validateAddressForm(formData);
    if (gstConfig.enabled) {
      newErrors.gst = validateGstField(formData.gst, {
        required: gstConfig.required,
      });
    }

    setErrors(newErrors);

    const hasError = Object.values(newErrors).some((msg) => msg !== "");
    if (hasError) return;

    if (gstConfig.enabled && formData.gst && formData.gst.trim()) {
      addCartAttributesWithOtpStore({
        [gstConfig.label]: formData.gst.trim().toUpperCase(),
      });
    }

    setOtpData({ isLoading: true });

    const { firstName: first_name, lastName: last_name } = splitFullName(
      formData.fullName
    );
    const province = normalizeProvince(formData.state);
    const filledAddress = {
      ...addressTemplate,
      address1: formData.address1,
      address2: formData.address2,
      city: formData.city,
      first_name: first_name || "",
      last_name: last_name || "",
      zip: formData.pincode,
      province,
      formatted: JSON.stringify([
        formData.address1,
        formData.city,
        province,
        formData.pincode,
      ]),
      formatted_area: `${formData.city}, ${province}`,
    };

    let shippingAddresses = getSessionValue("shipping_addresses") || [];
    if (isEditAddress && editableAddress) {
      const index = shippingAddresses.findIndex(
        (address) => address.id === editableAddress.id
      );
      if (index !== -1) {
        shippingAddresses[index] = {
          ...shippingAddresses[index],
          address1: formData.address1,
          address2: formData.address2,
          city: formData.city,
          first_name: first_name || "",
          last_name: last_name || "",
          zip: formData.pincode,
          province,
          formatted: JSON.stringify([
            formData.address1,
            formData.city,
            province,
            formData.pincode,
          ]),
          formatted_area: `${formData.city}, ${province}`,
        };
      } else {
        console.error("Editable address not found in shipping addresses.");
      }
    } else {
      shippingAddresses.push(filledAddress);
    }
    setSessionValue("shipping_addresses", shippingAddresses);

    processAddressSubmission(formData);

    // const customerId = getSessionValue("customer-id");
    const verifiedNumberData = getSessionValue("verifiedNumberData");
    const phone = verifiedNumberData?.otpVerifiedPhoneNumber;
    // const customerEmail = formData?.email;
    // setSessionValue("customer-email", formData?.email);
    // updateShippingAddresses({ phone, email: customerEmail, shippingAddresses })
    const customerEmail = formData?.email || "";

    setSessionValue("customer-email", customerEmail);

    updateShippingAddresses({ phone, email: customerEmail, shippingAddresses })
      .then((data) => {
        debugLog("Shipping addresses updated successfully:", data);
      })
      .catch((error) => {
        console.error("Error updating shipping addresses:", error);
      });
  };

  const processAddressSubmission = async (selected) => {
    if (selected) {
      debugLog("🏠 Processing address submission with OtpStore");

      const verifiedNumberData = getSessionValue("verifiedNumberData");
      const verifiedPhoneNumber = verifiedNumberData?.otpVerifiedPhoneNumber;

      // Create selected object in the format expected by buildBuyerIdentityPayload
      const selectedForPayload = {
        email: selected.email,
        first_name: selected.fullName.split(" ")[0],
        last_name: selected.fullName.split(" ").slice(1).join(" ") || "",
        address1: selected.address1,
        address2: selected.address2 || "",
        city: selected.city,
        state: selected.state,
        zip: selected.pincode,
      };

      debugLog("🔍 DEBUG - Selected for payload:", selectedForPayload);

      try {
        setOtpData({ isLoading: true });

        // ✅ Use OtpStore instead of the non-existent CartStore
        const buyerIdentityPayload = buildBuyerIdentityPayload(
          selectedForPayload,
          verifiedPhoneNumber
        );

        if (buyerIdentityPayload) {
          debugLog("✅ Buyer identity payload built successfully");

          // ✅ Set identity in store
          setBuyerIdentity(buyerIdentityPayload);

          // Update cart with buyer identity
          const currentCartData = useOtpStore.getState().currentCartData;
          const cartToken =
            currentCartData?.token || getSessionValue("shopify_cart")?.token;
          if (cartToken) {
            const cartId = getStorefrontCartId(cartToken);
            if (cartId) {
              try {
                debugLog(
                  "🔄 Updating cart with buyer identity on address add/edit"
                );
                await updateBuyerIdentity(cartId, buyerIdentityPayload);
                debugLog("✅ Cart updated with buyer identity successfully");
              } catch (error) {
                console.error(
                  "Error updating cart with buyer identity:",
                  error
                );
                // Don't throw - address submission should still work even if cart update fails
              }
            }
          }

          // Mark address completion
          setIsPrefilledAddressCompleted(true);

          // Move to next step
          const currentStep = await getCurrentStep();
          setStep(currentStep);

          setOtpData({ isLoading: false });

          debugLog("✅ Address submission completed using OtpStore");
        } else {
          throw new Error("Failed to build buyer identity payload");
        }
      } catch (error) {
        console.error(
          "❌ Failed to update buyer identity via OtpStore:",
          error
        );

        setOtpData({
          isLoading: false,
          error:
            error?.message ||
            (typeof error === "string" ? error : "Something went wrong."),
        });
      }
    }
  };
  const fieldLabel = (key) =>
    labels[key] ? <TitleSubtle>{labels[key]}</TitleSubtle> : null;

  return (
    <AddressFormContainerCODK>
      {shippingAddresses && shippingAddresses.length > 0 && (
        <BackToAddressesButtonCODK onClick={() => setStep(3)}>
          <ArrowLeft size={16} />
          Back to addresses
        </BackToAddressesButtonCODK>
      )}

      <TitleCODK>
        {isEditAddress ? "Edit delivery address" : "Add delivery address"}
      </TitleCODK>

      <FormCODK onSubmit={handleFormSubmit}>
        {/* Section: Address Details */}
        <TitleSubtle>Address Details</TitleSubtle>

        {/* Pincode */}
        <FormGroupCODK>
          {fieldLabel("pincode")}
          <InputCODK
            placeholder={placeholders.pincode}
            name="pincode"
            value={formData.pincode}
            onChange={handleInputChange}
            hasError={!!errors.pincode}
          />
          {loadingPincode && (
            <div style={{ fontSize: "13px", color: "#6b7280" }}>
              Validating pincode...
            </div>
          )}
          {errors.pincode && <ErrorTextCODK>{errors.pincode}</ErrorTextCODK>}
        </FormGroupCODK>

        {/* City/State */}
        <RowCODK>
          <FormGroupCODK style={{ flex: 1 }}>
            {fieldLabel("city")}
            <InputCODK
              placeholder={placeholders.city}
              name="city"
              value={formData.city}
              onChange={handleInputChange}
              // disabled={!errors.city}
              hasError={!!errors.city}
            />
            {errors.city && <ErrorTextCODK>{errors.city}</ErrorTextCODK>}
          </FormGroupCODK>
          <FormGroupCODK style={{ flex: 1 }}>
            {fieldLabel("state")}
            <InputCODK
              placeholder={placeholders.state}
              name="state"
              value={formData.state}
              onChange={handleInputChange}
              // disabled={!errors.state}
              hasError={!!errors.state}
            />
            {errors.state && <ErrorTextCODK>{errors.state}</ErrorTextCODK>}
          </FormGroupCODK>
        </RowCODK>

        {/* Divider */}
        <div style={{ height: "8px" }} />

        {/* Section: Contact Details */}
        <TitleSubtle>Contact Details</TitleSubtle>

        {/* Full Name */}
        <FormGroupCODK>
          {fieldLabel("name")}
          <InputCODK
            placeholder={placeholders.name}
            name="fullName"
            value={formData.fullName}
            onChange={handleInputChange}
            hasError={!!errors.fullName}
          />
          {errors.fullName && <ErrorTextCODK>{errors.fullName}</ErrorTextCODK>}
        </FormGroupCODK>

        {/* Email */}
        {/* {settings?.preEmailMandatory && (
          <FormGroupCODK>
            <InputCODK
              placeholder="Email"
              name="email"
              value={formData.email}
              onChange={handleInputChange}
              hasError={!!errors.email}
            />
            {errors.email && <ErrorTextCODK>{errors.email}</ErrorTextCODK>}
          </FormGroupCODK>
        )} */}

        {/* {(settings?.preEmailMandatory && !getSessionValue("customer-email")) ||
        otpData.error === "Email is invalid" ||
        errors.email === "Invalid email format" ? ( */}
        <FormGroupCODK>
          {fieldLabel("email")}
          <InputCODK
            placeholder={placeholders.email}
            name="email"
            value={formData.email}
            onChange={handleInputChange}
            hasError={otpData.error === "Email is invalid" || !!errors.email}
          />
          {(otpData.error === "Email is invalid" || errors.email) && (
            <ErrorTextCODK>
              {otpData.error === "Email is invalid"
                ? otpData.error
                : errors.email}
            </ErrorTextCODK>
          )}
        </FormGroupCODK>

        {/* Area / Street */}
        <FormGroupCODK>
          {fieldLabel("address1")}
          <TextAreaCODK
            placeholder={placeholders.address1}
            name="address1"
            value={formData.address1}
            onChange={handleInputChange}
            hasError={!!errors.address1}
          />
          {errors.address1 && <ErrorTextCODK>{errors.address1}</ErrorTextCODK>}
        </FormGroupCODK>

        {/* House No. / Apartment */}
        <FormGroupCODK>
          {fieldLabel("address2")}
          <TextAreaCODK
            placeholder={placeholders.address2}
            name="address2"
            value={formData.address2}
            onChange={handleInputChange}
          />
        </FormGroupCODK>

        {/* GST Number (optional merchant-enabled field) */}
        {gstConfig.enabled && (
          <FormGroupCODK>
            <TitleSubtle>
              {gstConfig.label}
              {gstConfig.required ? " *" : ""}
            </TitleSubtle>
            <InputCODK
              placeholder={gstConfig.placeholder}
              name="gst"
              value={formData.gst}
              onChange={handleInputChange}
              hasError={!!errors.gst}
            />
            {errors.gst && <ErrorTextCODK>{errors.gst}</ErrorTextCODK>}
          </FormGroupCODK>
        )}

        {/* Global Error */}
        {otpData.error && <ErrorTextCODK>*{otpData.error}</ErrorTextCODK>}

        {/* Submit */}
        <div style={{ marginTop: "24px" }}>
          <ButtonCODK type="submit" disabled={!isCartReady}>
            {isLoading ? <Loader size={16} /> : "Save & Continue →"}
          </ButtonCODK>
        </div>
      </FormCODK>
    </AddressFormContainerCODK>
  );
}

export default AddOrEditAddress;

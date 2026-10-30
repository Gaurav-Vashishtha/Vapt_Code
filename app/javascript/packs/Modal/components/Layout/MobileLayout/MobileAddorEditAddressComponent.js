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

import { ArrowLeft } from "lucide-react";

import debounce from "lodash.debounce";
import StickyFooterWithSummary from "./MobileStickyFooterWithSummary";
import CodkingButton from "../CommonComponent/codKingButton";

const MobileContainer = styled.div`
  max-width: 448px;
  margin: 0 auto;
  font-family: sans-serif;
  height: 100vh; /* Take full height of viewport */
  overflow-y: auto; /* Enable vertical scroll */

  box-sizing: border-box;
  -webkit-overflow-scrolling: touch; /* Smooth scrolling on iOS */
`;

const AddressFormContainerCODK = styled.div`
  width: 100%;
  // max-width: 480px;
  margin: 0 auto;
  // background: #ffffff;
  border-radius: 10px;
  // box-shadow: 0 6px 18px rgba(0, 0, 0, 0.1);
  // padding: 15px;
  display: flex;
  flex-direction: column;
  overflow-y: auto;
  margin-top: 40px !important;
`;

const TitleCODK = styled.div`
  font-size: 16px;
  line-height: 22px;
  font-weight: bold;
  color: #1f1f1f;
`;

const FormCODK = styled.form`
  display: flex;
  flex-direction: column;
  gap: 10px;
`;

const FormGroupCODK = styled.div`
  display: flex;
  flex-direction: column;
  gap: 3px;
`;

const ErrorTextCODK = styled.div`
  color: #dc2626;
  font-size: 12px;
  margin-top: 3px;
`;

const RowCODK = styled.div`
  display: flex;
  gap: 10px;
`;

const ButtonContainer = styled.div`
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background: white;
  padding: 10px;
  box-shadow: 0 -2px 10px rgba(0, 0, 0, 0.1);
  z-index: 10;
`;

const ButtonCODK = styled.button`
  width: 100%;
  padding: 12px;
  background-color: ${(props) => props.bgColor || props.theme.primary};
  color: ${(props) => props.textColor || props.theme.secondary};
  border: none;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  transition: background-color 0.3s ease-in-out, transform 0.2s ease-in-out;
  box-shadow: 0px 3px 5px rgba(0, 0, 0, 0.1);

  &:active {
    transform: scale(0.98);
  }

  &:disabled {
    background-color: ${(props) => props.disabledBgColor || props.theme.border};
    color: ${(props) => props.disabledTextColor || props.theme.text};
    cursor: not-allowed;
  }
`;

const InputCODK = styled.input`
  width: 100%;
  padding: 10px 12px;
  border: 1px solid
    ${({ hasError, theme }) =>
      hasError ? "#e53935" : theme.border || "#D9DEE3"};
  border-radius: 6px;
  font-size: 13px;
  color: ${(props) => props.theme.text || "#1E1E1E"};
  background: ${(props) => props.theme.inputBg || "#FFFFFF"};

  &::placeholder {
    color: ${({ hasError }) => (hasError ? "#e53935" : "#9ca3af")};
    font-size: 11px;
  }

  &:focus {
    outline: none;
    border-color: ${({ hasError, theme }) =>
      hasError ? "#e53935" : theme.primary || "#DA768D"};
    box-shadow: ${({ hasError }) =>
      hasError ? "0 0 0 2px rgba(229, 57, 53, 0.2)" : "none"};
  }

  &:disabled {
    background-color: #f3f4f6;
    color: #9ca3af;
    cursor: not-allowed;
  }
`;

const TitleSubtle = styled.div`
  font-size: 13px;
  font-weight: 600;
  color: #4b5563;
  margin-top: 6px;
  margin-bottom: 3px;
`;

const TextAreaCODK = styled.textarea`
  width: 100%;
  height: 50px;
  padding: 10px 12px;
  border: 1px solid ${(props) => props.theme.border || "#e5e7eb"};
  border-radius: 6px;
  font-size: 13px;
  color: ${(props) => props.theme.textDark || "#1f2937"};
  background: ${(props) => props.theme.inputBg || "#f9fafb"};
  resize: vertical;

  &::placeholder {
    color: #9ca3af;
    font-size: 11px;
  }

  &:disabled {
    background-color: #f3f4f6;
    color: #9ca3af;
    cursor: not-allowed;
  }
`;

const BackToAddressesButtonCODK = styled.button`
  display: flex;
  align-items: center;
  gap: 10px;
  background: none;
  border: none;
  font-size: 13.5px;
  font-weight: 600;
  cursor: pointer;
  padding: 0;
  margin-bottom: 10px;
  color: ${(props) => props.theme.link || props.theme.primary || "#4f46e5"};

  &:hover {
    color: ${(props) =>
      props.theme.linkHover || props.theme.primaryDark || "#4338ca"};
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
    currentCartData,
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
      }
    } catch (error) {
      console.error("Error fetching zip details:", error);
    } finally {
      setLoadingPincode(false);
    }
  }, 500);

  const handleFormSubmit = async (e) => {
    e.preventDefault();

    const newErrors = validateAddressForm(formData);
    if (gstConfig.enabled) {
      newErrors.gst = validateGstField(formData.gst, {
        required: gstConfig.required,
      });
    }

    setErrors(newErrors);
    if (Object.values(newErrors).some((msg) => msg !== "")) return;

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
          ...filledAddress,
        };
      }
    } else {
      shippingAddresses.push(filledAddress);
    }
    setSessionValue("shipping_addresses", shippingAddresses);

    // ✅ Updated to use OtpStore
    await processAddressSubmission(formData);

    const verifiedNumberData = getSessionValue("verifiedNumberData");
    const phone = verifiedNumberData?.otpVerifiedPhoneNumber;
    const customerEmail = formData?.email || "";
    setSessionValue("customer-email", customerEmail);

    updateShippingAddresses({ phone, email: customerEmail, shippingAddresses })
      .then((data) =>
        debugLog("Shipping addresses updated successfully:", data)
      )
      .catch((error) =>
        console.error("Error updating shipping addresses:", error)
      );
  };

  // ✅ Updated processAddressSubmission to use OtpStore
  const processAddressSubmission = async (selected) => {
    if (selected) {
      debugLog("🏠 Processing address submission with OtpStore");

      const verifiedNumberData = getSessionValue("verifiedNumberData");
      const verifiedPhoneNumber = verifiedNumberData?.otpVerifiedPhoneNumber;

      // ✅ Create selected object in expected format
      const selectedForPayload = {
        email: selected.email,
        first_name: selected.fullName.split(" ")[0],
        last_name: selected.fullName.split(" ").slice(1).join(" ") || "",
        address1: selected.address1,
        address2: selected.address2 || "",
        city: selected.city,
        state: selected.state, // Note: using 'state' not 'province'
        zip: selected.pincode, // Note: using 'pincode' for zip
      };

      debugLog("🔍 DEBUG - Form data for payload:", selectedForPayload);

      try {
        setOtpData({ isLoading: true });

        // ✅ Use OtpStore instead of the non-existent CartStore
        const buyerIdentityPayload = buildBuyerIdentityPayload(
          selectedForPayload,
          verifiedPhoneNumber
        );

        if (buyerIdentityPayload) {
          debugLog("✅ Buyer identity built successfully from form submission");

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

          // ✅ Continue with normal flow
          setOtpData({ isLoading: false });
          setIsPrefilledAddressCompleted(true);

          const currentStep = await getCurrentStep();
          setStep(currentStep);

          debugLog("✅ Form submission completed using OtpStore");
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
    <MobileContainer>
      <AddressFormContainerCODK>
        <br />
        {shippingAddresses && shippingAddresses.length > 0 && (
          <BackToAddressesButtonCODK onClick={() => setStep(3)}>
            <ArrowLeft size={18} />
            Back to addresses
          </BackToAddressesButtonCODK>
        )}
        <TitleCODK>
          {isEditAddress ? "Edit delivery address" : "Add delivery address"}
        </TitleCODK>
        <FormCODK>
          <TitleSubtle>Address Details</TitleSubtle>
          <FormGroupCODK>
            {fieldLabel("pincode")}
            <InputCODK
              placeholder={placeholders.pincode}
              name="pincode"
              value={formData.pincode}
              onChange={handleInputChange}
            />
            {loadingPincode && (
              <div style={{ fontSize: "12px", color: "#6b7280" }}>
                Validating pincode...
              </div>
            )}
            {errors.pincode && <ErrorTextCODK>{errors.pincode}</ErrorTextCODK>}
          </FormGroupCODK>
          <RowCODK>
            <FormGroupCODK style={{ flex: 1 }}>
              {fieldLabel("city")}
              <InputCODK
                placeholder={placeholders.city}
                name="city"
                value={formData.city}
                onChange={handleInputChange}
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
              />
              {errors.state && <ErrorTextCODK>{errors.state}</ErrorTextCODK>}
            </FormGroupCODK>
          </RowCODK>
          <TitleSubtle>Contact Details</TitleSubtle>
          <FormGroupCODK>
            {fieldLabel("name")}
            <InputCODK
              placeholder={placeholders.name}
              name="fullName"
              value={formData.fullName}
              onChange={handleInputChange}
            />
            {errors.fullName && (
              <ErrorTextCODK>{errors.fullName}</ErrorTextCODK>
            )}
          </FormGroupCODK>
          {/* {(settings?.preEmailMandatory &&
            !getSessionValue("customer-email")) ||
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

          <FormGroupCODK>
            {fieldLabel("address1")}
            <TextAreaCODK
              placeholder={placeholders.address1}
              name="address1"
              value={formData.address1}
              onChange={handleInputChange}
            />
            {errors.address1 && (
              <ErrorTextCODK>{errors.address1}</ErrorTextCODK>
            )}
          </FormGroupCODK>
          <FormGroupCODK>
            {fieldLabel("address2")}
            <TextAreaCODK
              placeholder={placeholders.address2}
              name="address2"
              value={formData.address2}
              onChange={handleInputChange}
            />
          </FormGroupCODK>
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
          {otpData.error && <ErrorTextCODK>*{otpData.error}</ErrorTextCODK>}
        </FormCODK>
      </AddressFormContainerCODK>
      <br />
      <StickyFooterWithSummary>
        <CodkingButton
          onClick={handleFormSubmit}
          disabled={!isCartReady}
          loading={isLoading}
        >
          Save & Continue
        </CodkingButton>
      </StickyFooterWithSummary>
    </MobileContainer>
  );
}

export default AddOrEditAddress;

import React, { useEffect, useMemo, useState } from "react";
import styled from "styled-components";
import AddOrEditAddress from "./DesktopAddorEditAddressComponent";
import useOtpStore from "../../../stores/otpStore";
import {
  debugLog,
  getSessionValue,
  setSessionValue,
} from "../../../utilities/otpUtils";
import { updateShippingAddresses } from "../../../services/otpService";
import CodkingButton from "../CommonComponent/codKingButton";

const DeliveryContainerCODK = styled.div`
  margin-top: 24px !important;
  max-height: 300px !important;
  overflow-y: auto !important;
`;

const DeliveryHeaderCODK = styled.div`
  display: flex !important;
  justify-content: space-between !important;
  align-items: center !important;
  margin-bottom: 24px !important;
`;

const AddNewButtonCODK = styled.button`
  background-color: #ffffff;
  color: ${(props) => props.theme.primary || "#2563eb"};
  border: 1px solid ${(props) => props.theme.primary || "#2563eb"};
  padding: 10px 20px;
  border-radius: 6px;
  font-weight: 600;
  font-size: 14px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 8px;
  transition: all 0.2s ease-in-out;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);

  &:hover {
    background-color: ${(props) => props.theme.primary || "#2563eb"};
    color: #ffffff;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    transform: translateY(-1px);
  }

  &:active {
    transform: translateY(0);
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);
  }

  &:focus {
    outline: none;
    box-shadow: 0 0 0 3px ${(props) => props.theme.primary || "#2563eb"}20;
  }

  &:disabled {
    opacity: 0.6;
    cursor: not-allowed;
    transform: none;

    &:hover {
      background-color: #ffffff;
      color: ${(props) => props.theme.primary || "#2563eb"};
      box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);
    }
  }
`;

// const DeliveryAddressCardCODK = styled.div`
//   border: 2px solid ${(props) => props.theme.primary} !important;
//   border-radius: 12px !important;
//   padding: 16px !important;
//   margin-bottom: 16px !important;
//   background-color: ${(props) =>
//     props.isSelected ? props.theme.cardBg : props.theme.background} !important;
//   font-weight: ${(props) => (props.isSelected ? "bold" : "normal")} !important;
//   color: ${(props) =>
//     props.isSelected ? props.theme.text : "#666"} !important;
//   position: relative !important;
//   cursor: pointer !important;
// `;

const DeliveryAddressCardCODK = styled.div`
  border: 1px solid
    ${(props) =>
      props.isSelected ? props.theme.primary || "#2563eb" : "#e5e7eb"};
  border-radius: 8px;
  padding: 20px;
  margin-bottom: 12px;
  background-color: ${(props) => (props.isSelected ? "#fafbff" : "#ffffff")};
  font-weight: ${(props) => (props.isSelected ? "500" : "400")};
  color: ${(props) =>
    props.isSelected ? props.theme.text || "#111827" : "#6b7280"};
  position: relative;
  cursor: pointer;
  transition: all 0.2s ease-in-out;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);

  &:hover {
    border-color: ${(props) => props.theme.primary || "#2563eb"};
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);
    transform: translateY(-1px);
  }

  ${(props) =>
    props.isSelected &&
    `
    border-width: 2px;
    box-shadow: 0 0 0 1px ${
      props.theme.primary || "#2563eb"
    }15, 0 8px 16px rgba(0, 0, 0, 0.06);

    &::before {
      content: "";
      position: absolute;
      top: 0;
      left: 0;
      width: 4px;
      height: 100%;
      background-color: ${props.theme.primary || "#2563eb"};
      border-radius: 8px 0 0 8px;
    }
  `}

  &:focus-within {
    outline: none;
    border-color: ${(props) => props.theme.primary || "#2563eb"};
    box-shadow: 0 0 0 3px ${(props) => props.theme.primary || "#2563eb"}20;
  }

  &:active {
    transform: translateY(0);
  }

  /* Selected state indicator */
  ${(props) =>
    props.isSelected &&
    `
    &::after {

      position: absolute;
      top: 16px;
      right: 16px;
      width: 20px;
      height: 20px;
      background-color: ${props.theme.primary || "#2563eb"};
      color: white;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 12px;
      font-weight: 600;
    }
  `}

  /* Responsive design */
  @media (max-width: 768px) {
    padding: 16px;
    margin-bottom: 8px;
  }
`;

const SelectedBadgeCODK = styled.div`
  background-color: ${(props) => props.theme.primary} !important;
  color: ${(props) => props.theme.background} !important;
  padding: 4px 8px !important;
  border-radius: 8px !important;
  font-size: 12px !important;
  font-weight: bold !important;
  position: absolute !important;
  top: 8px !important;
  right: 16px !important;
`;

const AddressLabelCODK = styled.div`
  display: flex !important;
  align-items: center !important;
  gap: 8px !important;
  margin-bottom: 12px !important;
`;

const AddressDetailsCODK = styled.div`
  color: #666 !important;
  margin-bottom: 12px !important;
`;

const EditButtonCODK = styled.button`
  background: none !important;
  border: none !important;
  color: ${(props) => props.theme.primary} !important;
  cursor: pointer !important;
  font-size: 14px !important;
  display: flex !important;
  align-items: center !important;
  gap: 4px !important;
  margin-top: 8px !important;
  float: right !important;
`;

const ButtonCODK = styled.button`
  width: 100% !important;
  min-width: 160px !important;
  padding: 12px 24px !important;
  background-color: ${(props) =>
    props.bgColor || props.theme.primary} !important;
  color: ${(props) => props.textColor || props.theme.secondary} !important;
  border: none !important;
  border-radius: 30px !important;
  font-size: 12.5px !important;
  font-weight: 600 !important;
  cursor: pointer !important;
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  gap: 8px !important;
  transition: background-color 0.3s ease-in-out, box-shadow 0.3s,
    transform 0.2s ease-in-out !important;
  box-shadow: 0px 4px 6px rgba(0, 0, 0, 0.1) !important;

  &:hover {
    background-color: ${(props) =>
      props.hoverBgColor || props.theme.primaryDark} !important;
    box-shadow: 0px 6px 12px rgba(0, 0, 0, 0.2) !important;
  }

  &:active {
    transform: scale(0.97) !important;
    box-shadow: inset 0px 3px 6px rgba(0, 0, 0, 0.2) !important;
  }

  &:disabled {
    background-color: ${(props) =>
      props.disabledBgColor || props.theme.border} !important;
    color: ${(props) => props.disabledTextColor || props.theme.text} !important;
    cursor: not-allowed !important;
    box-shadow: none !important;
  }
`;

const DeliveryTitleCODK = styled.div`
  font-size: 20px !important;
  line-height: 28px !important;
  font-weight: 600 !important;
  --tw-text-opacity: 1;

  @media (max-width: 768px) {
    font-size: 20px !important;
    line-height: 28px !important;
    font-weight: 599 !important;
  }
`;

const FormGroupCODK = styled.div`
  margin-bottom: 20px !important;
`;

const InputCODK = styled.input`
  width: 100% !important;
  padding: 12px !important;
  border: 1px solid ${(props) => (props.hasError ? "red" : props.theme.border)} !important;
  border-radius: 8px !important;
  font-size: 14px !important;
  color: ${(props) => props.theme.text} !important;

  &:focus {
    outline: none !important;
    border-color: ${(props) =>
      props.hasError ? "red" : props.theme.primary} !important;
  }
`;

const ErrorTextCODK = styled.div`
  color: red !important;
  font-size: 12px !important;
  margin-top: 4px !important;
`;

const DeliveryAddressCODK = ({ theme }) => {
  const {
    otpData,
    handleContinue,
    handleAddressSelect,
    handleEditAddress,
    handleAddAddress,
    selectedAddress,
    setOtpData,
    isCartManipulationProcessCompleted,
    setStep,
    isCartReady,
  } = useOtpStore();

  const { isLoading } = otpData;
  const verifiedNumberData = getSessionValue("verifiedNumberData");
  const verifiedPhoneNumber =
    verifiedNumberData?.otpVerifiedPhoneNumber || otpData?.phoneNumber;
  const preOrderOtpResponse = getSessionValue("preOrderOtpResponse");
  const settings = getSessionValue("settingSession");
  // State for shipping addresses and loading state
  const [shippingAddresses, setShippingAddress] = useState(
    () => getSessionValue("shipping_addresses") || []
  );
  const [isFetching, setIsFetching] = useState(true); // Track data fetching

  // State for form data and errors
  const [formData, setFormData] = useState({
    email: "",
  });

  const [errors, setErrors] = useState({});

  useEffect(() => {
    const sessionEmail = getSessionValue("customer-email");
    if (sessionEmail) {
      setFormData((prev) => ({ ...prev, email: sessionEmail }));
    }
  }, []);
  // Fetch addresses properly **without triggering an infinite loop**
  useEffect(() => {
    const sessionAddresses = getSessionValue("shipping_addresses") || [];

    if (
      sessionAddresses.length === 0 &&
      preOrderOtpResponse?.shippingAddress?.length > 0
    ) {
      setSessionValue(
        "shipping_addresses",
        preOrderOtpResponse.shippingAddress
      );
      setShippingAddress(preOrderOtpResponse.shippingAddress);
    } else if (sessionAddresses.length > 0 && shippingAddresses.length === 0) {
      setShippingAddress(sessionAddresses);
    }

    setIsFetching(false); // Mark fetching as completed
  }, []); // ✅ Runs only once when the component mounts

  // Format addresses for UI
  const addresses = useMemo(
    () =>
      shippingAddresses.map((item, index) => ({
        id: index,
        addressId: item.id,
        first_name: item.first_name || "",
        last_name: item.last_name || "",
        address1: item.address1 || "N/A",
        address2: item.address2 || "",
        city: item.city || "N/A",
        province: item.province || "N/A",
        zip: item.zip || "N/A",
        phone: item.phone || verifiedPhoneNumber,
      })),
    [shippingAddresses, verifiedPhoneNumber]
  );

  // Handle address selection safely
  useEffect(() => {
    if (!isFetching) {
      if (addresses.length > 0) {
        setOtpData((prev) => ({ ...prev, currentProgressBarStep: 1 }));
        if (
          !selectedAddress ||
          !addresses.some(
            (a) => String(a.addressId) === String(selectedAddress)
          )
        ) {
          // Auto-pick first address AND prefill buyer identity (no click needed)
          void handleAddressSelect(addresses[0].addressId);
        }
      } else {
        setStep(4); // Redirect only after confirming addresses are empty
      }
    }
  }, [
    addresses,
    isFetching,
    selectedAddress,
    setOtpData,
    handleAddressSelect,
    setStep,
  ]);

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setOtpData((prev) => ({ ...prev, error: "" }));

    setFormData((prev) => ({
      ...prev,
      [name]: value,
    }));

    const fieldError = validateField(name, value);
    setErrors((prev) => ({
      ...prev,
      [name]: fieldError,
    }));
  };

  const validateField = (name, value) => {
    if (name === "email") {
      if (!value.trim()) {
        return "Email is required";
      }
      const emailRegex = /^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/;
      if (!emailRegex.test(value)) {
        return "Invalid email format";
      }
    }
    return "";
  };

  const validateForm = () => {
    const newErrors = {
      email: validateField("email", formData.email),
    };

    setErrors(newErrors);

    return !Object.values(newErrors).some((msg) => msg !== "");
  };

  const handleContinueClick = async () => {
    try {
      setOtpData((prev) => ({ ...prev, isLoading: true }));
      if (settings?.preEmailMandatory) {
        if (!validateForm()) return;

        await setSessionValue("customer-email", formData?.email); // wait to set
      } else if (formData?.email) {
        if (!validateForm()) return;
        await setSessionValue("customer-email", formData?.email);
      }
      handleContinue(); // only after session set
      const data = await updateShippingAddresses({
        phone: verifiedPhoneNumber,
        email: formData?.email || "",
        shippingAddresses,
      });
      debugLog("Shipping addresses updated successfully:", data);
    } catch (error) {
      console.error("Error in handleContinueClick:", error);
    }
  };

  return (
    <div>
      <div>
        <DeliveryHeaderCODK>
          <DeliveryTitleCODK>
            Delivery address ({shippingAddresses?.length})
          </DeliveryTitleCODK>
          <AddNewButtonCODK theme={theme} onClick={() => handleAddAddress()}>
            <span style={{ fontSize: "18px" }}>+</span>
            Add new
          </AddNewButtonCODK>
        </DeliveryHeaderCODK>
        <DeliveryContainerCODK>
          {addresses?.map((address) => (
            <DeliveryAddressCardCODK
              key={address.id}
              theme={theme}
              isSelected={String(selectedAddress) === String(address.addressId)}
              onClick={() => handleAddressSelect(address.addressId)}
            >
              {String(selectedAddress) === String(address.addressId) && (
                <SelectedBadgeCODK theme={theme}>Selected</SelectedBadgeCODK>
              )}
              <AddressLabelCODK>
                <strong>
                  {address.first_name} {address.last_name} • {address.phone}
                </strong>
              </AddressLabelCODK>

              <EditButtonCODK
                theme={theme}
                onClick={() => handleEditAddress(address.addressId)}
              >
                <span style={{ marginRight: "4px" }}>✎</span> Edit
              </EditButtonCODK>

              <AddressDetailsCODK>
                {address.address1}, {address.address2}, {address.city},{" "}
                {address.province}, {address.zip}
              </AddressDetailsCODK>
            </DeliveryAddressCardCODK>
          ))}
        </DeliveryContainerCODK>
        {otpData.error && <ErrorTextCODK>*{otpData.error}</ErrorTextCODK>}
        {errors.email && <ErrorTextCODK>*{errors.email}</ErrorTextCODK>}
      </div>

      <br />
      {/* <ButtonCODK
        theme={theme}
        onClick={handleContinueClick}
        disabled={isLoading || !isCartManipulationProcessCompleted}
      >
        {isLoading ? <LuLoader /> : "Continue" || "Continue"}
      </ButtonCODK> */}
      <CodkingButton
        onClick={handleContinueClick}
        disabled={!isCartReady}
        loading={isLoading}
      >
        Continue
      </CodkingButton>
    </div>
  );
};

export default DeliveryAddressCODK;

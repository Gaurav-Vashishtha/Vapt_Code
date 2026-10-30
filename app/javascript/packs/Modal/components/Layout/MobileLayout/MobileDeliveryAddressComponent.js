import React, { useEffect, useMemo, useState } from "react";
import styled from "styled-components";
import AddOrEditAddress from "../DesktopLayout/DesktopAddorEditAddressComponent";
import useOtpStore from "../../../stores/otpStore";
import {
  debugLog,
  getSessionValue,
  setSessionValue,
} from "../../../utilities/otpUtils";

import { updateShippingAddresses } from "../../../services/otpService";
import CodkingButton from "../CommonComponent/codKingButton";
import StickyFooter from "./MobileFooterSection";
import StickyFooterWithSummary from "./MobileStickyFooterWithSummary";

// const Container = styled.div`
//   margin-top: 15%;
// `;

const Container = styled.div`
  margin-top: ${({ addressCount }) => {
    if (addressCount <= 1) return "6% !important";
    if (addressCount === 2) return "10% !important";
    if (addressCount === 3) return "12% !important";
    return "15% !important";
  }};
  padding-bottom: 5px !important; /* No padding needed since footer is not fixed */
`;

const Header = styled.div`
  display: flex !important;
  justify-content: space-between !important;
  align-items: center !important;
  margin-bottom: 20px !important;
  padding: 0 4px !important;
`;

const Title = styled.h2`
  font-family: revert !important;
  font-size: 20px !important;
  font-weight: 600 !important;
  color: #1a1a1a !important;
  margin: 0 !important;
`;

const AddButton = styled.button`
  background: none !important;
  border: none !important;
  color: #686868 !important;
  font-size: 14px !important;
  font-weight: 500 !important;
  cursor: pointer !important;
  display: flex !important;
  align-items: center !important;
  gap: 4px !important;
  padding: 8px !important;
  border-radius: 6px !important;

  &:hover {
    background-color: rgba(0, 123, 255, 0.1) !important;
  }

  .plus-icon {
    font-size: 16px !important;
    font-weight: 600 !important;
  }
`;

const AddressCardWrapper = styled.label`
  position: relative !important;
  cursor: pointer !important;
  display: block !important;
  margin-bottom: 16px !important;
`;

const HiddenRadio = styled.input`
  position: absolute !important;
  z-index: -10 !important;
  height: 100% !important;
  width: 100% !important;
  opacity: 0 !important;
  pointer-events: none !important;
`;

const OuterCard = styled.div`
  cursor: pointer !important;
  border-radius: 12px !important;
  background-color: ${(props) =>
    props.isSelected
      ? "rgba(0, 0, 0, 0.03) !important"
      : "transparent !important"}; // light gray/black tint
  color: ${(props) =>
    props.isSelected
      ? "#111827 !important"
      : "#374151 !important"}; // darker text on select
  border: 1px solid
    ${(props) =>
      props.isSelected
        ? "#9CA3AF !important"
        : "transparent !important"}; // neutral gray border
  ${(props) =>
    props.isSelected &&
    `
    box-shadow: 0 0 0 2px rgba(0, 0, 0, 0.06) !important; // soft subtle shadow
  `}
  transition: all 0.2s ease !important;
`;

// const OuterCard = styled.div`
//   cursor: pointer;
//   border-radius: 12px;
//   background-color: ${(props) =>
//     props.isSelected ? "rgba(37, 99, 235, 0.03)" : "transparent"};
//   color: ${(props) => (props.isSelected ? "#1e40af" : "#374151")};
//   border: 1px solid ${(props) => (props.isSelected ? "#2563eb" : "transparent")};
//   ${(props) =>
//     props.isSelected &&
//     `
//     box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.1);
//   `}
//   transition: all 0.2s ease;
// `;

const InnerCard = styled.div`
  position: relative !important;
  display: block !important;
  width: 100% !important;
  border-radius: 12px !important;
  background-color: white !important;
  padding: 16px !important;
  text-align: left !important;
  color: #111827 !important;
  border: 1px solid transparent !important;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1) !important;
`;

const AddressHeader = styled.div`
  display: flex !important;
  align-items: center !important;
  justify-content: space-between !important;
  gap: 8px !important;
  margin-bottom: 12px !important;
`;

const AddressTypeSection = styled.span`
  display: inline-flex !important;
  align-items: center !important;
  justify-content: between !important;
  gap: 6px !important;
`;

const IconWrapper = styled.span`
  position: relative !important;
  display: flex !important;
  flex-shrink: 0 !important;
`;

const HomeIcon = styled.span`
  display: inline-flex !important;
  height: 16px !important;
  align-items: center !important;
  color: #838383 !important;
  svg {
    height: 100% !important;
    width: 16px !important;
  }
`;

const AddressTypeText = styled.span`
  font-weight: 500 !important;
  text-transform: capitalize !important;
  line-height: 1.25 !important;
  color: #111827 !important;
  font-size: 14px !important;
`;

const EditButton = styled.button`
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  background: none !important;
  border: none !important;
  cursor: pointer !important;
  padding: 4px !important;
  border-radius: 4px !important;
  color: #838383 !important;

  &:hover {
    background-color: rgba(37, 99, 235, 0.1) !important;
  }

  svg {
    height: 16px !important;
    width: 16px !important;
  }
`;

const AddressContent = styled.div`
  margin-top: 12px !important;
  padding-top: 12px !important;
  border-top: 1px dashed rgba(108, 132, 157, 0.15) !important;
`;

const CustomerInfo = styled.p`
  font-weight: 500 !important;
  margin: 0 0 4px 0 !important;
  font-size: 14px !important;
  color: #111827 !important;
`;

const AddressText = styled.p`
  margin: 4px 0 0 0 !important;
  word-break: break-word !important;
  color: rgba(17, 24, 39, 0.6) !important;
  font-size: 14px !important;
  line-height: 1.4 !important;
`;

const ShippingSection = styled.p`
  overflow: hidden !important;
  text-overflow: ellipsis !important;
  white-space: nowrap !important;
  padding: 12px 16px !important;
  font-size: 14px !important;
  font-weight: 500 !important;
  color: rgba(107, 114, 128, 0.7) !important;
  margin: 0 !important;

  &:empty {
    display: none !important;
  }
`;

const ShippingContent = styled.span`
  display: flex !important;
  align-items: center !important;
  gap: 8px !important;
  color: #838383 !important;
`;

const CheckIcon = styled.span`
  display: inline-flex !important;
  height: 16px !important;
  align-items: center !important;
  flex-shrink: 0 !important;

  svg {
    height: 100% !important;
    width: 16px !important;
  }
`;

const Dot = styled.span`
  color: rgba(107, 114, 128, 0.2) !important;
`;

const ShippingText = styled.span`
  overflow: hidden !important;
  text-overflow: ellipsis !important;
  color: #374151 !important;
`;

const FreeBadge = styled.span`
  border-radius: 4px !important;
  padding: 2px 6px !important;
  font-weight: 600 !important;
  background-color: #059669 !important;
  color: white !important;
  margin-left: auto !important;
  font-size: 12px !important;
`;

const EmailSection = styled.div`
  background: white !important;
  border-radius: 12px !important;
  padding: 16px !important;
  margin-bottom: 20px !important;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1) !important;
`;

const FormGroup = styled.div`
  margin-bottom: 16px !important;
`;

const Label = styled.label`
  display: block !important;
  font-size: 14px !important;
  font-weight: 500 !important;
  color: #111827 !important;
  margin-bottom: 8px !important;
`;

const Input = styled.input`
  width: 100% !important;
  padding: 12px 16px !important;
  border: 1px solid
    ${(props) => (props.hasError ? "#dc3545 !important" : "#d1d5db !important")};
  border-radius: 8px !important;
  font-size: 14px !important;
  color: #111827 !important;
  background-color: white !important;
  box-sizing: border-box !important;

  &::placeholder {
    color: #6b7280 !important;
  }

  &:focus {
    outline: none !important;
    border-color: ${(props) =>
      props.hasError ? "#dc3545 !important" : "#2563eb !important"};
    box-shadow: 0 0 0 3px
      ${(props) =>
        props.hasError
          ? "rgba(220, 53, 69, 0.1) !important"
          : "rgba(37, 99, 235, 0.1) !important"};
  }
`;

const ErrorText = styled.div`
  color: #dc3545 !important;
  font-size: 12px !important;
  margin-top: 4px !important;
  display: flex !important;
  align-items: center !important;
  gap: 4px !important;
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
  const [isFetching, setIsFetching] = useState(true);

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

  // Fetch addresses properly
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

    setIsFetching(false);
  }, []);

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

  // Handle address selection
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
        setStep(4);
      }
    }
  }, [addresses, isFetching, selectedAddress, setOtpData, handleAddressSelect, setStep]);

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
        await setSessionValue("customer-email", formData?.email);
      } else if (formData?.email) {
        if (!validateForm()) return;
        await setSessionValue("customer-email", formData?.email);
      }
      handleContinue();
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
    <>
      <Container addressCount={shippingAddresses.length}>
        <Header>
          <Title>Delivery address ({shippingAddresses?.length})</Title>
          <AddButton onClick={() => handleAddAddress()}>
            <span className="plus-icon">+</span>
            Add new
          </AddButton>
        </Header>

        <div
          style={{
            marginBottom: "0px",
            maxHeight: "300px",
            overflowY: "auto",
          }}
        >
          {addresses?.map((address) => (
            <AddressCardWrapper key={address.id}>
              <HiddenRadio
                type="radio"
                name={`address-${address.id}`}
                checked={String(selectedAddress) === String(address.addressId)}
                onChange={() => handleAddressSelect(address.addressId)}
              />
              <OuterCard isSelected={String(selectedAddress) === String(address.addressId)}>
                <InnerCard>
                  <div>
                    <AddressHeader>
                      <AddressTypeSection>
                        <IconWrapper>
                          <HomeIcon>
                            <svg
                              xmlns="http://www.w3.org/2000/svg"
                              fill="none"
                              viewBox="0 0 16 16"
                            >
                              <path
                                fill="currentColor"
                                fillOpacity=".09"
                                d="M2.5 13.5V6.69L8 1.976l5.5 4.714v6.81H11V11a3 3 0 1 0-6 0v2.5H2.5Z"
                              />
                              <path
                                fill="currentColor"
                                fillRule="evenodd"
                                d="M8 9.5A1.5 1.5 0 0 0 6.5 11v4H1V6l7-6 7 6v9H9.5v-4A1.5 1.5 0 0 0 8 9.5ZM8 8a3 3 0 0 0-3 3v2.5H2.5V6.69L8 1.976l5.5 4.714v6.81H11V11a3 3 0 0 0-3-3Z"
                                clipRule="evenodd"
                              />
                            </svg>
                          </HomeIcon>
                        </IconWrapper>
                        <span>
                          <AddressTypeText>Address</AddressTypeText>
                        </span>
                      </AddressTypeSection>
                      <EditButton
                        onClick={(e) => {
                          e.stopPropagation();
                          handleEditAddress(address.addressId);
                        }}
                      >
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 16 16"
                        >
                          <path
                            fill="currentColor"
                            fillOpacity=".09"
                            fillRule="evenodd"
                            d="M2.5 13.503v-2.379l6.78-6.78 2.379 2.378-6.78 6.78H2.5Z"
                            clipRule="evenodd"
                          />
                          <path
                            fill="currentColor"
                            fillRule="evenodd"
                            d="M15.068 5.432 5.5 15H1v-4.5L10.568.932a3.182 3.182 0 0 1 4.5 4.5ZM2.5 13.5v-2.379l6.78-6.78 2.38 2.379-6.78 6.78H2.5Zm10.22-7.841 1.287-1.288a1.682 1.682 0 0 0-2.378-2.378L10.34 3.28l2.38 2.38Z"
                            clipRule="evenodd"
                          />
                        </svg>
                      </EditButton>
                    </AddressHeader>
                  </div>
                  <AddressContent>
                    <CustomerInfo>
                      <span>
                        {address.first_name} {address.last_name}
                      </span>
                      {" • "}
                      {address.phone}
                    </CustomerInfo>
                    <AddressText>
                      {address.address1}
                      {address.address2 && `, ${address.address2}`},{" "}
                      {address.city}, {address.province}, {address.zip}
                    </AddressText>
                  </AddressContent>
                </InnerCard>
                <ShippingSection>
                  <ShippingContent>
                    <CheckIcon>
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 16 16"
                      >
                        <path
                          fill="currentColor"
                          d="m12.28 5.78-1.06-1.06L6.5 9.44 4.78 7.72 3.72 8.78l2.78 2.78 5.78-5.78Z"
                        />
                        <path
                          fill="currentColor"
                          fillRule="evenodd"
                          d="M16 8A8 8 0 1 1 0 8a8 8 0 0 1 16 0Zm-1.5 0a6.5 6.5 0 1 1-13 0 6.5 6.5 0 0 1 13 0Z"
                          clipRule="evenodd"
                        />
                      </svg>
                    </CheckIcon>
                    <Dot>•</Dot>
                    <ShippingText>Standard Shipping</ShippingText>
                    {/* <FreeBadge>FREE</FreeBadge> */}
                  </ShippingContent>
                </ShippingSection>
              </OuterCard>
            </AddressCardWrapper>
          ))}
        </div>
      </Container>
      <StickyFooterWithSummary>
        {otpData.error && otpData.error !== "Email is invalid" && (
          <ErrorText style={{ marginBottom: "16px" }}>
            ⚠ {otpData.error}
          </ErrorText>
        )}
        <CodkingButton
          onClick={handleContinueClick}
          disabled={!isCartReady}
          loading={isLoading}
        >
          Continue
        </CodkingButton>
      </StickyFooterWithSummary>

      {/* <StickyFooter>
        {otpData.error && otpData.error !== "Email is invalid" && (
          <ErrorText style={{ marginBottom: "16px" }}>
            ⚠ {otpData.error}
          </ErrorText>
        )}

        <CodkingButton
          onClick={handleContinueClick}
          disabled={!isCartReady}
          loading={isLoading}
        >
          Continue
        </CodkingButton>
      </StickyFooter> */}
    </>
  );
};

export default DeliveryAddressCODK;

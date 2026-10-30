import React, { useState, useEffect } from "react";
import styled from "styled-components";
import { useAppContext } from "../../context/AppContext";
import {
  debugLog,
  getSessionValue,
  setSessionValue,
} from "../../utilities/otpUtils";
import { updateBuyerIdentity } from "../../services/cartService";
// import useModalStore from "../../stores/modalStore";
import useOtpStore from "../../stores/otpStore";

const Container = styled.div`
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica,
    Arial, sans-serif;
  max-width: 600px;
  margin: 0 auto;
  padding: 20px;
`;

const Header = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
`;

const IconButton = styled.button`
  background: none;
  border: none;
  font-size: 20px;
  cursor: pointer;
  color: #333;
`;

const Title = styled.h2`
  font-size: 22px;
  font-weight: 600;
  margin-bottom: 20px;
  color: #333;
`;

const ProgressBar = styled.div`
  display: flex;
  justify-content: space-between;
  margin-bottom: 24px;
`;

const ProgressStep = styled.div`
  flex: 1;
  text-align: center;
`;

const StepText = styled.div`
  font-size: 14px;
  font-weight: 500;
  color: ${(props) => (props.active ? "#333" : "#777")};
`;

const StepIndicator = styled.div`
  height: 3px;
  background-color: ${(props) => (props.active ? "#333" : "#e0e0e0")};
  margin-top: 4px;
`;

const Form = styled.form`
  display: flex;
  flex-direction: column;
  gap: 15px;
`;

const Input = styled.input`
  width: 100%;
  padding: 10px;
  border: 1px solid #ccc;
  border-radius: 4px;
  font-size: 14px;
  &:focus {
    outline: none;
    border-color: #555;
  }
`;

const InputGroup = styled.div`
  display: flex;
  gap: 15px;
`;

// const Button = styled.button`
//   width: 100%;
//   padding: 12px;
//   background-color: #333;
//   color: white;
//   border: none;
//   border-radius: 4px;
//   font-size: 16px;
//   font-weight: 600;
//   cursor: pointer;
//   transition: background-color 0.3s;
//   &:hover {
//     background-color: #555;
//   }
// `;

const Button = styled.button`
  width: 100%;
  padding: 12px;
  background-color: ${(props) =>
    props.theme.primary}; /* Button background depends on primary */
  color: ${(props) =>
    props.theme.secondary}; /* Button text color depends on secondary */
  border: none;
  border-radius: 4px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;

  &:hover {
    background-color: ${(props) =>
      props.theme.primaryDark}; /* Darker shade for hover */
    color: ${(props) => props.theme.secondary}; /* Text color stays the same */
  }

  &:disabled {
    background-color: ${(props) =>
      props.theme.border}; /* Use border color for disabled state */
    color: ${(props) =>
      props.theme.text}; /* Use text color for disabled state */
    cursor: not-allowed;
  }
`;

const Footer = styled.div`
  display: flex;
  justify-content: flex-end;
  align-items: center;
  margin-top: 20px;
  font-size: 12px;
  color: #777;
`;

const addressTemplate = {
  address1: "", // Street address (e.g., "123 Main St")
  address2: "", // Additional address info (e.g., "Apt 4B")
  city: "", // City name (e.g., "New York")
  company: null, // Company name (if applicable)
  coordinates_validated: null, // Boolean or validation status
  country: "", // Country name (e.g., "United States")
  country_code: null, // Country code (e.g., "US")
  country_code_v2: "", // Two-letter ISO code (e.g., "US")
  country_name: null, // Optional additional country name
  created_at: new Date().toISOString(), // Creation timestamp
  customer_id: null, // Customer ID (if applicable)
  default: null, // Boolean to indicate default address
  first_name: "", // Customer's first name (e.g., "John")
  formatted: "", // JSON string of formatted address (optional)
  formatted_area: "", // Formatted area (e.g., "New York, USA")
  id: null, // Unique identifier for the address
  last_name: "", // Customer's last name (e.g., "Doe")
  latitude: null, // Latitude coordinate (optional)
  longitude: null, // Longitude coordinate (optional)
  phone: "", // Phone number (e.g., "1234567890")
  province: "", // State or province (e.g., "New York")
  province_code: "", // Province code (e.g., "NY")
  shopify_id: "", // Shopify address ID (if applicable)
  updated_at: new Date().toISOString(), // Last updated timestamp
  zip: "", // Postal or ZIP code (e.g., "10001")
};

function AddOrEditAddress({ setStep }) {
  // const { settings, selectedCountry, valid, phone } = useAppContext();
  const { editableAddress, isEditAddress } = useOtpStore(); //useModalStore();

  const [formData, setFormData] = useState({
    fullName: "",
    address: "",
    pincode: "",
    city: "",
    state: "",
    email: "",
  });

  useEffect(() => {
    debugLog("isEditAddress", isEditAddress);

    if (isEditAddress == true) {
      setFormData({
        fullName: editableAddress.name,
        address: editableAddress.address,
        pincode: editableAddress.zip,
        city: editableAddress.city,
        state: editableAddress.state,
        email: editableAddress.email,
      });
    }
    debugLog("inside step 4");
  }, [isEditAddress]);

  let shippingAddresses = [];
  useEffect(() => {
    shippingAddresses = getSessionValue("shipping_addresses");
    debugLog("shippingAddresses from shipping view page", shippingAddresses);
  }, []);

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData((prevState) => ({
      ...prevState,
      [name]: value,
    }));
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    debugLog("Form submitted:", formData);
    const [first_name, last_name] = formData.fullName.split(" ");
    const filledAddress = {
      ...addressTemplate,
      address1: formData.address,
      city: formData.city,
      first_name: first_name || "",
      last_name: last_name || "",
      zip: formData.pincode,
      province: formData.state,
      province_code: formData.state.slice(0, 2).toUpperCase(), // Example: "qq" from "qqqq"
      formatted: JSON.stringify([
        formData.address,
        formData.city,
        formData.state,
        formData.pincode,
      ]),
      formatted_area: `${formData.city}, ${formData.state}`,
      shopify_id: null, // You can fill this with any ID or keep it null
    };

    debugLog(filledAddress);
    shippingAddresses.push(filledAddress);
    debugLog("shippingAddresses updated", filledAddress);
    // setSessionValue("shipping_addresses", shippingAddresses);

    // setShippingAddress(shippingAddresses);
    handleContinue(formData);
    // resetAddressState();
    const customerId = getSessionValue("customer-id");
    sendShippingAddress({ customerId, shippingAddresses })
      .then((result) => debugLog("Shipping address sent successfully:", result))
      .catch((error) =>
        console.error("Failed to send shipping address:", error)
      );
  };
  const verifiedNumberData = getSessionValue("verifiedNumberData");
  const verifiedPhoneNumber = verifiedNumberData?.otpVerifiedPhoneNumber;
  const handleContinue = async (selected) => {
    if (selected) {
      debugLog("selected", selected);
      // Construct the `buyerIdentity` object following Shopify's schema
      const buyerIdentity = {
        email: selected.email,
        phone: verifiedPhoneNumber,
        countryCode: "IN", // Set your appropriate country code
        deliveryAddressPreferences: [
          {
            deliveryAddress: {
              address1: selected.address.split(" ")[0],
              address2: selected.address.split(" ")[1] || "",
              city: selected.city,
              province: selected.state,
              country: "India",
              zip: selected.pincode,
              firstName: selected.fullName,
              phone: verifiedPhoneNumber,
            },
          },
        ],
      };

      try {
        // let cartId = shopifyCreatedCart?.id;
        let createdCart = getSessionValue("created-cart");
        let cartId = createdCart?.id;
        debugLog("verifiedPhoneNumber", verifiedPhoneNumber);
        debugLog("cart id", cartId);
        debugLog("buyerIdentity", buyerIdentity);

        // Call the mutation to update the buyer identity
        const updatedCart = await updateBuyerIdentity(cartId, buyerIdentity);

        debugLog("Updated Cart:", updatedCart);

        // Useful for inspecting state during development
        window.location.href = updatedCart?.checkoutUrl;
        // setStep(5); // Proceed to the next step on success
      } catch (error) {
        console.error("Failed to update buyer identity:", error);
        // Handle the error (show a message to the user if needed)
      }
    } else {
      console.error("No address selected");
      // Optionally, show an error message to the user if no address is selected
    }
  };

  return (
    <>
      {" "}
      <span onClick={() => setStep(3)}> Back </span>
      <Title>Add Address</Title>
      <Form onSubmit={handleSubmit}>
        <Input
          type="text"
          name="fullName"
          placeholder="Full Name"
          value={formData.fullName}
          onChange={handleInputChange}
          required
        />
        <Input
          type="text"
          name="address"
          placeholder="Address (House no, Building, Street, Area)"
          value={formData.address}
          onChange={handleInputChange}
          required
        />
        <InputGroup>
          <Input
            type="text"
            name="pincode"
            placeholder="Pincode"
            value={formData.pincode}
            onChange={handleInputChange}
            required
          />
          <Input
            type="text"
            name="city"
            placeholder="City"
            value={formData.city}
            onChange={handleInputChange}
            required
          />
          <Input
            type="text"
            name="state"
            placeholder="State"
            value={formData.state}
            onChange={handleInputChange}
            required
          />
        </InputGroup>
        <Input
          type="email"
          name="email"
          placeholder="Email"
          value={formData.email}
          onChange={handleInputChange}
          required
        />
        <Button type="submit">Save & Continue →</Button>
      </Form>
    </>
  );
}

export default AddOrEditAddress;

// import React, { useState, useEffect } from "react";
// import styled from "styled-components";
// import { useAppContext } from "../../context/AppContext";
// import { createCart, updateBuyerIdentity } from "../../services/cartService";
// import {
//   debugLog,
//   getSessionValue,
//   removeSessionValue,
//   setSessionValue,
// } from "../../utilities/otpUtils";
// // import useModalStore from "../../stores/modalStore";
// import { getCart } from "../../services/otpService";
// import { IS_BUY_NOW_BUTTON } from "../../services/domUtils";
// import useOtpStore from "../../stores/otpStore";

// const Container = styled.div`
//   background-color: white;
//   border-top-left-radius: 12px;
//   border-top-right-radius: 12px;
//   max-width: 400px;
//   margin: 0 auto;
//   box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
// `;

// const Header = styled.div`
//   display: flex;
//   justify-content: space-between;
//   align-items: center;
//   padding: 16px;
//   border-bottom: 1px solid #e5e7eb;
// `;

// const IconButton = styled.button`
//   background: none;
//   border: none;
//   cursor: pointer;
//   font-size: 24px;
// `;

// const Content = styled.div`
//   padding: 24px;
// `;

// const ProgressBar = styled.div`
//   display: flex;
//   justify-content: space-between;
//   margin-bottom: 24px;
// `;

// const ProgressStep = styled.div`
//   flex: 1;
//   text-align: center;
// `;

// const StepText = styled.div`
//   font-size: 14px;
//   font-weight: 500;
//   color: ${(props) => (props.active ? "black" : "#6b7280")};
// `;

// const StepIndicator = styled.div`
//   height: 4px;
//   background-color: ${(props) => (props.active ? "black" : "#e5e7eb")};
//   border-radius: 2px;
//   margin-top: 4px;
// `;

// const Title = styled.h2`
//   font-size: 24px;
//   font-weight: bold;
//   margin-bottom: 16px;
// `;

// const AddButton = styled.button`
//   width: 100%;
//   padding: 8px;
//   background-color: white;
//   border: 1px solid #e5e7eb;
//   border-radius: 4px;
//   display: flex;
//   justify-content: space-between;
//   align-items: center;
//   margin-bottom: 16px;
//   cursor: pointer;
// `;

// const AddressCard = styled.div`
//   border: 1px solid #e5e7eb;
//   border-radius: 8px;
//   padding: 16px;
//   margin-bottom: 16px;
//   position: relative;
// `;

// const CheckIcon = styled.span`
//   position: absolute;
//   top: 16px;
//   right: 16px;
//   color: #10b981;
// `;

// const EditButton = styled.button`
//   background: none;
//   border: none;
//   color: #4b5563;
//   cursor: pointer;
//   display: flex;
//   align-items: center;
//   margin-top: 8px;
// `;

// const ContinueButton = styled.button`
//   width: 100%;
//   padding: 12px;
//   background-color: black;
//   color: white;
//   border: none;
//   border-radius: 4px;
//   font-weight: bold;
//   cursor: pointer;
//   display: flex;
//   justify-content: center;
//   align-items: center;
// `;

// const Footer = styled.div`
//   padding: 16px;
//   display: flex;
//   justify-content: flex-end;
//   align-items: center;
//   font-size: 12px;
//   color: #6b7280;
// `;
// const AddressList = styled.div`
//   max-height: 300px; /* Set a specific height */
//   overflow-y: auto; /* Enable vertical scrolling */
//   margin-bottom: 16px;

//   /* Optional scrollbar styling */
//   &::-webkit-scrollbar {
//     width: 8px;
//   }
//   &::-webkit-scrollbar-track {
//     background: #f1f1f1;
//     border-radius: 10px;
//   }
//   &::-webkit-scrollbar-thumb {
//     background: #888;
//     border-radius: 10px;
//   }
//   &::-webkit-scrollbar-thumb:hover {
//     background: #555;
//   }
// `;
// // let dummyAddress = [
// //   {
// //     id: 17970,
// //     first_name: "Aman",
// //     last_name: "deep",
// //     company: null,
// //     address1: "test",
// //     address2: "test",
// //     city: "bangalore",
// //     province: "Karnataka",
// //     country: "India",
// //     zip: "560035",
// //     phone: null,
// //     province_code: "KA",
// //     country_code: null,
// //     country_name: null,
// //     formatted: '["test", "test", "560035 bangalore KA", "India"]',
// //     formatted_area: "bangalore KA, India",
// //     latitude: null,
// //     longitude: null,
// //     coordinates_validated: null,
// //     country_code_v2: "IN",
// //     shopify_id:
// //       "gid://shopify/MailingAddress/8952695718163?model_name=CustomerAddress",
// //     default: null,
// //     created_at: "2024-08-28T10:20:24.492Z",
// //     updated_at: "2024-08-28T10:20:24.492Z",
// //     customer_id: 12264,
// //   },
// //   {
// //     id: 17971,
// //     first_name: "Aman",
// //     last_name: "deep",
// //     company: null,
// //     address1: "test",
// //     address2: "test",
// //     city: "bangalore",
// //     province: "Karnataka",
// //     country: "India",
// //     zip: "560034",
// //     phone: "91307 51989",
// //     province_code: "KA",
// //     country_code: null,
// //     country_name: null,
// //     formatted: '["test", "test", "560034 bangalore KA", "India"]',
// //     formatted_area: "bangalore KA, India",
// //     latitude: null,
// //     longitude: null,
// //     coordinates_validated: null,
// //     country_code_v2: "IN",
// //     shopify_id:
// //       "gid://shopify/MailingAddress/8952697028883?model_name=CustomerAddress",
// //     default: null,
// //     created_at: "2024-08-28T10:20:24.496Z",
// //     updated_at: "2024-08-28T10:20:24.496Z",
// //     customer_id: 12264,
// //   },
// // ];
// function ShippingAddress({ setStep }) {
//   // const { settings, selectedCountry, valid, phone } = useAppContext();
//   const { setIsEditAddress, setEditableAddress, otpData } = useOtpStore();
//   const { phoneNumber } = otpData;
//   const [selectedAddress, setSelectedAddress] = useState(0);

//   let shippingAddresses = getSessionValue("shipping_addresses"); //|| dummyAddress;
//   debugLog("shippingAddresses from shipping view page", shippingAddresses);

//   const addresses = shippingAddresses?.map((item, index) => ({
//     id: index,
//     name: `${item.first_name} ${item.last_name}`,
//     address: `${item.address1} ${item.address2}`.trim(),
//     city: item.city,
//     state: item.province,
//     zip: item.zip,
//     email: getSessionValue("customer-email"), // Static email for all addresses
//   }));
//   const verifiedNumberData = getSessionValue("verifiedNumberData");
//   const verifiedPhoneNumber =
//     verifiedNumberData?.otpVerifiedPhoneNumber || phoneNumber;

//   const handleContinue = async () => {
//     // Step 1: Retrieve the selected address
//     const selected = addresses.find(
//       (address) => address.id === selectedAddress
//     );

//     // Step 2: Validate that an address is selected
//     if (!selected) {
//       console.error("No address selected");
//       // Optionally show an error message to the user
//       return;
//     }

//     try {
//       // Step 3: Check if a cart is already created in the session
//       const createdCart = getSessionValue("created-cart");

//       if (createdCart) {
//         // Step 4a: Update the existing cart's buyer identity
//         const buyerIdentity = createBuyerIdentity(
//           selected,
//           verifiedPhoneNumber
//         );
//         await handleCartUpdate(createdCart.id, buyerIdentity);
//       } else {
//         // Step 4b: Create a new cart based on the button action
//         await handleCartCreation(selected, verifiedPhoneNumber);
//       }
//     } catch (error) {
//       console.error("Failed to handle cart process:", error);
//       // Handle the error (e.g., show a message to the user if needed)
//     }
//   };

//   /**
//    * Creates a buyer identity object based on Shopify's schema
//    */
//   function createBuyerIdentity(selected, phone) {
//     return {
//       email: selected.email,
//       phone: phone, // Use phone number from the state/context
//       countryCode: "IN", // Set your appropriate country code
//       deliveryAddressPreferences: [
//         {
//           deliveryAddress: {
//             address1: selected.address.split(" ")[0],
//             address2: selected.address.split(" ")[1] || "",
//             city: selected.city,
//             province: selected.state,
//             country: "India",
//             zip: selected.zip,
//             firstName: selected.name,
//             phone: phone,
//           },
//         },
//       ],
//     };
//   }

//   /**
//    * Updates an existing cart with the buyer identity information
//    */
//   async function handleCartUpdate(cartId, buyerIdentity) {
//     try {
//       debugLog("Updating cart with ID:", cartId);
//       const updatedCart = await updateBuyerIdentity(cartId, buyerIdentity);
//       debugLog("Updated Cart:", updatedCart);

//       // Remove cart from session and redirect to checkout URL
//       removeSessionValue("created-cart");
//       window.location.href = updatedCart?.checkoutUrl;
//     } catch (error) {
//       console.error("Error updating buyer identity:", error);
//       throw error;
//     }
//   }

//   /**
//    * Handles cart creation for Buy Now or regular cart flow
//    */
//   async function handleCartCreation(selected, phone) {
//     const cartVariables = IS_BUY_NOW_BUTTON
//       ? createBuyNowCartVariables(selected, phone)
//       : await createRegularCartVariables(selected, phone);

//     if (cartVariables) {
//       try {
//         const cart = await createCart(cartVariables);
//         await getCart(true);
//         debugLog("Cart created:", cart);

//         // Remove cart from session and redirect to checkout URL
//         removeSessionValue("created-cart");
//         window.location.href = cart?.checkoutUrl;
//       } catch (error) {
//         console.error("Error creating cart:", error);
//         throw error;
//       }
//     }
//   }

//   /**
//    * Constructs cart variables for the "Buy Now" button flow
//    */
//   function createBuyNowCartVariables(selected, phone) {
//     const variantSelect = document.querySelector('[name="id"]');
//     const quantityInput = document.querySelector('[name="quantity"]');
//     const variantID = variantSelect?.value;
//     const quantity = quantityInput ? parseInt(quantityInput.value, 10) : 1;

//     debugLog("Buy Now - variantID, quantity:", variantID, quantity);
//     return buildCartVariables(
//       [
//         {
//           quantity: quantity,
//           merchandiseId: `gid://shopify/ProductVariant/${variantID}`,
//         },
//       ],
//       selected,
//       phone
//     );
//   }

//   /**
//    * Constructs cart variables for a regular cart based on existing cart items
//    */
//   async function createRegularCartVariables(selected, phone) {
//     try {
//       const cartData = await getCart();

//       if (cartData.items.length > 0) {
//         const lines = cartData.items.map((item) => ({
//           quantity: item.quantity,
//           merchandiseId: `gid://shopify/ProductVariant/${item.variant_id}`,
//         }));
//         debugLog("Line Items:", lines);
//         return buildCartVariables(lines, selected, phone);
//       } else {
//         console.error("No items in the cart");
//         return null;
//       }
//     } catch (error) {
//       console.error("Error fetching cart data:", error);
//       throw error;
//     }
//   }

//   /**
//    * Helper function to build the cart variables for mutation
//    */
//   function buildCartVariables(lines, selected, phone) {
//     return {
//       lines: lines,
//       email: selected.email,
//       countryCode: window.Shopify.country,
//       firstName: selected.name,
//       address1: selected.address,
//       address2: "",
//       city: selected.city,
//       province: selected.state,
//       country: window.Shopify.country,
//       zip: selected.zip,
//       phone: phone, // Pass the phone number explicitly
//       cartAttributeKey: "cart_attribute",
//       cartAttributeValue: "This is a cart attribute",
//     };
//   }

//   function handleAddressSelect(id) {
//     setSelectedAddress(id);
//   }

//   function handleEditAddress() {
//     const selected = addresses.find(
//       (address) => address.id === selectedAddress
//     );
//     debugLog("here inside handle edit addresss", selected);
//     setIsEditAddress(true);
//     setEditableAddress(selected);
//     setStep(4);
//   }
//   const handleAddAddress = (e) => {
//     // e.stopPropagation();
//     setStep(4);
//     debugLog("here clicking step 4");
//     setStep(4);
//     // setStep((prevState) => {
//     //   debugLog("Previous Step:", prevState); // Previous step state
//     //   return 4; // New step value
//     // });
//   };
//   return (
//     <>
//       <Content>
//         <span onClick={() => setStep(2)}> Back </span>
//         <Title>Shipping Address</Title>
//         <AddButton onClick={(e) => handleAddAddress(e)}>
//           <span>+ Add a new address</span>
//         </AddButton>
//         <AddressList>
//           {addresses.map((address) => (
//             <AddressCard
//               key={address.id}
//               onClick={() => handleAddressSelect(address.id)}
//             >
//               {selectedAddress === address.id && <CheckIcon>✓</CheckIcon>}
//               <p>{address.name}</p>
//               <p>{address.address}</p>
//               <p>
//                 {address.city}, {address.state}, {address.zip}
//               </p>
//               <p>{address.email}</p>
//               <EditButton onClick={handleEditAddress}>
//                 <span style={{ marginRight: "4px" }}>✎</span> Edit
//               </EditButton>
//             </AddressCard>
//           ))}
//         </AddressList>
//         <ContinueButton onClick={() => handleContinue()}>
//           Continue <span style={{ marginLeft: "4px" }}>→</span>
//         </ContinueButton>
//       </Content>
//       <Footer>
//         Powered by{" "}
//         <span
//           style={{
//             marginLeft: "4px",
//             backgroundColor: "#e5e7eb",
//             width: "60px",
//             height: "16px",
//             display: "inline-block",
//           }}
//         ></span>
//       </Footer>
//     </>
//   );
// }

// export default ShippingAddress;

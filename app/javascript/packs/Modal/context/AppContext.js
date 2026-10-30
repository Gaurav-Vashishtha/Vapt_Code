// import React, {
//   createContext,
//   useState,
//   useContext,
//   useRef,
//   useEffect,
// } from "react";
// // Create a Context for the app
// const AppContext = createContext();

// // Custom hook for using the context in other components
// export const useAppContext = () => {
//   return useContext(AppContext);
// };

// // AppProvider component that wraps the entire app and provides context
// export const AppProvider = ({ children }) => {
//   // Example of global state
//   const [cartData, setCartData] = useState(null);
//   const [settings, setSettings] = useState({
//     enablePreOrderOtp: false,
//     otpWaitTimeInCodKSettings: 60,
//     maxTriesInCodKSettings: 5,
//     countryCodeList: [],
//     wrongOtpText: "",
//     verifyBtnText: "",
//     heading: "",
//     subHeading: "",
//     sendBtnText: "",
//     skipBtnText: "",
//     redirectText: "",
//     showSkipBtn: false,
//     prePrimaryButtonColor: "#000",
//     preSecondaryButtonColor: "#000",
//     prePrimaryButtonFontColor: "#fff",
//     preSecondaryButtonFontColor: "#fff",
//     preWhatsappButton: false,
//     preWhatsappButtonText: "",
//   });

//   const [otpCheckComplete, setOtpCheckComplete] = useState(false);
//   const isMounted = useRef(true);
//   const [phone, setPhone] = useState("");
//   const [valid, setValid] = useState(false);
//   const [selectedCountry, setSelectedCountry] = useState({});
//   React.useEffect(() => {
//     return () => {
//       isMounted.current = false;
//     };
//   }, []);

//   // Any other global state or functions can be added here
//   return (
//     <AppContext.Provider
//       value={{
//         cartData,
//         setCartData,
//         settings,
//         setSettings,
//         otpCheckComplete,
//         setOtpCheckComplete,
//         phone,
//         setPhone,
//         valid,
//         setValid,
//         selectedCountry,
//         setSelectedCountry,
//       }}
//     >
//       {children}
//     </AppContext.Provider>
//   );
// };

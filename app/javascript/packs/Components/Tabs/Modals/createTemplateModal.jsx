// import React, { useState, useCallback, useApi } from "react";
// import {
//   TextField,
//   Select,
//   Button,
//   Stack,
//   Banner,
//   TextContainer,
//   Heading,
//   FormLayout,
// } from "@shopify/polaris";
// import { debugLog } from "../../../Modal/utilities/otpUtils";

// const CreateTemplateForm = () => {
//   const [templateName, setTemplateName] = useState("");
//   const [senderID, setSenderID] = useState("");
//   const [dltTemplateID, setDltTemplateID] = useState("");
//   const [smsContentLanguage, setSmsContentLanguage] = useState("English");
//   const [smsContent, setSmsContent] = useState("");
//   const [messageType, setMessageType] = useState("Abandoned Cart"); // State for Message Type
//   const [error, setError] = useState({});

//   const [{ data: apiData, loading: apiLoading, error1 }, saveSettings] = useApi(
//     {
//       url: `https://${process.env.APP_HOST}/headers`,
//       method: "POST",
//     },
//     { manual: true }
//   );

//   const handleSettingChange = (key) => (value) => {
//     setStatus(null);
//     // useCallback((value) => {
//     if (key == "countryCodes") {
//       value = value.toString();
//       setSelectedCountries(value);
//     }
//     // });
//     setSetting({
//       ...setting,
//       [key]: value,
//     });
//     !contextualBar && setContextualBar(true);
//   };
//   useEffect(() => {
//     setSetting("");
//     setSelectedCountries("");
//     setStatus(null);
//   }, []);

//   const handleTemplateNameChange = useCallback(
//     (value) => setTemplateName(value),
//     []
//   );

//   const handleSenderIDChange = useCallback((value) => setSenderID(value), []);

//   const handleDltTemplateIDChange = useCallback(
//     (value) => setDltTemplateID(value),
//     []
//   );

//   const handleSmsContentLanguageChange = useCallback(
//     (value) => setSmsContentLanguage(value),
//     []
//   );

//   const handleSmsContentChange = useCallback(
//     (value) => setSmsContent(value),
//     []
//   );

//   const handleMessageTypeChange = useCallback(
//     (value) => setMessageType(value),
//     []
//   );

//   const handleSubmit = async () => {
//     if (!templateName || !senderID) {
//       setError({
//         templateName: !templateName ? "Template Name is required" : "",
//         senderID: !senderID ? "Sender ID is required" : "",
//       });
//       return;
//     }
//     //debugger;

//     // Handle form submission logic
//     debugLog({
//       messageType,
//       templateName,
//       senderID,
//       dltTemplateID,
//       smsContentLanguage,
//       smsContent,
//     });

//     if (plan.name == "Premium") {
//       setLoading(true);
//       try {
//         const resp = await saveSettings({ data: { header: setting } });
//         setLoading(false);

//         if (resp?.status === 200) {
//           setContextualBar(false);
//           setStatus(true);
//           setSetting("");
//           setSelectedCountries("");
//         } else {
//           setStatus(false);
//         }
//       } catch (error) {
//         setStatus(false);
//       }
//     } else {
//       setStatus("info");
//     }

//     // Clear form after submission
//     setMessageType("Abandoned Cart");
//     setTemplateName("");
//     setSenderID("");
//     setDltTemplateID("");
//     setSmsContentLanguage("English");
//     setSmsContent("");
//     setError({});
//   };

//   return (
//     <form onSubmit={handleSubmit}>
//       <FormLayout>
//         {/* Stack to align Message Type dropdown and Create button side by side */}

//         <div>
//           <Select
//             label="Message Type"
//             options={["Abandoned Cart", "Fulfilment", "Confirmation", "OTP"]}
//             value={messageType}
//             onChange={handleMessageTypeChange}
//           />
//         </div>

//         <FormLayout.Group>
//           <TextField
//             label="Template Name"
//             value={templateName}
//             onChange={handleTemplateNameChange}
//             error={error.templateName}
//             autoComplete="off"
//           />
//           <TextField
//             label="Sender ID"
//             value={senderID}
//             onChange={handleSenderIDChange}
//             error={error.senderID}
//             autoComplete="off"
//           />
//         </FormLayout.Group>

//         <TextField
//           label="DLT Template ID"
//           value={dltTemplateID}
//           onChange={handleDltTemplateIDChange}
//           autoComplete="off"
//         />

//         {/* Grouping SMS Content Dropdown and Message Field */}
//         <FormLayout.Group>
//           <Select
//             label="SMS Content"
//             options={["English"]}
//             value={smsContentLanguage}
//             onChange={handleSmsContentLanguageChange}
//           />
//           <TextField
//             label="Enter Message Here..."
//             value={smsContent}
//             onChange={handleSmsContentChange}
//             multiline={4}
//             autoComplete="off"
//           />
//         </FormLayout.Group>

//         <Button onClick={() => debugLog("Add Variable clicked")}>
//           + Add Variable
//         </Button>

//         <Banner status="info">
//           <TextContainer>
//             <Heading>Variables:</Heading>
//             <p>
//               Should be defined as ##name##, ##number##, ##email##, and so on.
//             </p>
//           </TextContainer>
//         </Banner>

//         {/* Stack component used to float the bottom Create button to the right */}
//         <Stack distribution="trailing">
//           <Button
//             primary
//             onClick={handleSubmit}
//             style={{ width: "200px" }} // Custom width for the Create button
//           >
//             Create
//           </Button>
//         </Stack>
//       </FormLayout>
//     </form>
//   );
// };

// export default CreateTemplateForm;

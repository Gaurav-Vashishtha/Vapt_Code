// import React, { useContext } from "react";
// import {
//   Card,
//   Button,
//   Stack,
//   Heading,
//   Link,
//   TextContainer,
//   Modal,
// } from "@shopify/polaris";

// import { StoreContext } from "../Context/Store";

// export function InstructionPage() {
//   const {
//     contextualBar: [contextualBar, setContextualBar],
//     shop: [shop],
//     setting: [setting, setSetting],
//     originalSetting: [originalSetting, setOriginalSetting],
//   } = useContext(StoreContext);

//   return (
//     <div
//       style={{
//         display: "flex",
//         gap: "32px",
//         maxWidth: "1200px",
//         margin: "0 auto",
//       }}
//     >
//       <Card sectioned style={{ flex: "1 1 auto", maxWidth: "800px" }}>
//         <Stack vertical spacing="loose">
//           <div>
//             <Heading>Enable Widget into your theme</Heading>
//             <p style={{ marginTop: "8px" }}>
//               Steps to enable the <strong>COD King Login</strong> app for your
//               store login page.
//             </p>
//           </div>
//           <Card title="Theme Integration">
//             <Card.Section>
//               <Stack alignment="center" distribution="equalSpacing">
//                 <TextContainer>
//                   <p>
//                     Enable OTP Box in your theme to activate OTP verification in
//                     your store.
//                   </p>
//                 </TextContainer>
//                 <Button
//                   primary
//                   external
//                   url={`https://${shop.shopify_domain}/admin/themes/current/editor?context=apps&template=cart&activateAppId=99553eb5-bf07-4ce0-9263-7e5f10cab22c/app-embed`}
//                 >
//                   Enable in Theme (Required)
//                 </Button>
//               </Stack>
//             </Card.Section>
//             <Card.Section>
//               <img
//                 src="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/extension.png?v=1732273929"
//                 alt="Enable the extension"
//                 style={{
//                   width: "100%",
//                   height: "auto",
//                   maxWidth: "600px",
//                   display: "block",
//                   margin: "0 auto",
//                 }}
//               />
//             </Card.Section>
//           </Card>

//           <Stack vertical spacing="tight">
//             <p>
//               Follow below steps to add <strong>Login with OTP</strong>:
//             </p>

//             <Stack vertical spacing="tight">
//               <p>
//                 <strong>Step 1:</strong> Go to your store{" "}
//                 <strong>{"Admin > Online Store > Themes"}</strong>.
//               </p>

//               <p>
//                 <strong>Step 2:</strong> Select the theme where App Embeds is
//                 enabled and click on the{" "}
//                 <code
//                   style={{
//                     background: "#F4F6F8",
//                     padding: "2px 6px",
//                     borderRadius: "4px",
//                   }}
//                 >
//                   Customize
//                 </code>{" "}
//                 button.
//               </p>

//               <p>
//                 <strong>Step 3:</strong> Select{" "}
//                 <strong>
//                   Classic{" "}
//                   <code
//                     style={{
//                       background: "#F4F6F8",
//                       padding: "2px 6px",
//                       borderRadius: "4px",
//                     }}
//                   >
//                     {"customer accounts > customer login"}
//                   </code>{" "}
//                 </strong>{" "}
//                 from page selector.
//               </p>

//               <p>
//                 <strong>Step 4:</strong> Navigate to{" "}
//                 <strong>{"Templates > Add Section > Apps"}</strong> then{" "}
//                 <strong>Customer Login With OTP</strong>, Place it in the
//                 desired location.
//               </p>

//               <p>
//                 <strong>Step 5:</strong> Deactivate the default login section by
//                 clicking on the eye icon associated with the{" "}
//                 <strong>Login</strong> section.
//               </p>

//               <p>
//                 <strong>Step 6:</strong> Once you have positioned the{" "}
//                 <strong>Customer Login With OTP</strong> click on the{" "}
//                 <code
//                   style={{
//                     background: "#F4F6F8",
//                     padding: "2px 6px",
//                     borderRadius: "4px",
//                   }}
//                 >
//                   save
//                 </code>{" "}
//                 button located in the top-right corner of the page to save your
//                 changes.
//               </p>
//             </Stack>
//           </Stack>
//         </Stack>
//       </Card>

//       <div style={{ width: "400px", flex: "0 0 auto" }}>
//         <Stack vertical spacing="tight">
//           <Card title="Learn how to setup OTP Login On your store" sectioned>
//             {/* <iframe width="420" height="315" src="https://www.youtube.com/embed/UghVNC3zTSc" frameborder="0" allowfullscreen></iframe>
//             //  */}

//             <div style={{ flex: 1 }}>
//               <div
//                 style={{
//                   position: "relative",
//                   paddingBottom: "33.25%",
//                   height: 0,
//                 }}
//               >
//                 <iframe
//                   style={{
//                     position: "absolute",
//                     top: 0,
//                     left: 0,
//                     width: "100%",
//                     height: "100%",
//                   }}
//                   src="https://www.youtube.com/embed/UghVNC3zTSc"
//                   title="Login with OTP Setup Tutorial"
//                   frameBorder="0"
//                   allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
//                   allowFullScreen
//                 />
//               </div>
//               <div style={{ marginTop: "0.5rem" }}>
//                 <p>
//                   <strong>Step by Step tutorial to setup Login with OTP</strong>
//                 </p>
//                 <Button
//                   size="slim"
//                   onClick={() =>
//                     window.open(
//                       "https://www.youtube.com/watch?v=UghVNC3zTSc",
//                       "_blank"
//                     )
//                   }
//                 >
//                   Open Video in New Tab
//                 </Button>
//               </div>
//             </div>
//           </Card>
//         </Stack>

//         <Card sectioned>
//           <Stack vertical spacing="tight">
//             <Heading>IMPORTANT NOTE:</Heading>
//             <ul style={{ paddingLeft: "20px", margin: "8px 0" }}>
//               <li style={{ marginBottom: "12px" }}>
//                 <p>
//                   Need help Setting it up?
//                   <Link
//                     external
//                     onClick={() => window.$crisp.push(["do", "chat:open"])}
//                   >
//                     Chat with us
//                   </Link>
//                   directly and we will help you enable the OTP widget with any
//                   of your login pages (including custom login pages)
//                 </p>
//               </li>
//               <li style={{ marginBottom: "12px" }}>
//                 Ensure that Legacy customer accounts are enabled to enable COD
//                 OTP login if not,{" "}
//                 <Link
//                   url={`https://${shop.shopify_domain}/admin/settings/customer_accounts`}
//                   external
//                 >
//                   {" "}
//                   click here
//                 </Link>
//               </li>
//               <li>
//                 {
//                   "Disabling the captcha from Online Store > Preferences > scroll down to the bottom and deselect the options highlighting the captcha."
//                 }
//               </li>
//             </ul>
//           </Stack>
//         </Card>
//       </div>
//     </div>
//   );
// }

// {
//   /* <Link
// url={`https://${shop.shopify_domain}/admin/settings/customer_accounts`}
// external>  click here</Link> */
// }

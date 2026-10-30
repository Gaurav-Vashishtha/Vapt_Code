// // Run this example by adding <%= javascript_pack_tag 'wish_oauth_react' %> to the head of your layout file,
// // like app/views/layouts/application.html.erb. All it does is render <div>Hello React</div> at the bottom
// // of the page.

// import React, { useState, useEffect } from "react";
// // import ReactDOM from "react-dom";
// import { createRoot } from "react-dom/client";
// import PropTypes from "prop-types";
// import { AppProvider } from "@shopify/polaris";
// import enTranslations from "@shopify/polaris/locales/en.json";
// import {
//   Layout,
//   Card,
//   EmptyState,
//   Spinner,
//   Icon,
//   Button,
//   Badge,
//   ResourceList,
//   Banner,
//   DescriptionList,
//   Stack,
// } from "@shopify/polaris";
// import { MobileAcceptMajor } from "@shopify/polaris-icons";
// import { useStorageState } from "react-storage-hooks";
// import useQueryString from "./Hooks/useQueryString";
// import useAxios from "axios-hooks";
// // import "@shopify/polaris/dist/styles.css";
// import "@shopify/polaris/build/esm/styles.css";
// import I18n, { availableLocales } from "./i18n-lang";
// // import Sentry from './Components/Ops/Sentry';

// const ConfirmButtons = ({ showCancelButton, autoVerify, order, shop }) => {
//   const order_id = useQueryString("order_id");
//   const otp = useQueryString("code");
//   const [error, setError] = useState(false);
//   const [cancelled, setCancelled] = useState(false);

//   const closeTab = () => {
//     window.opener = null;
//     window.open("", "_self");
//     window.close();
//   };

//   const [{ loading: confirmLoading }, onConfirm] = useAxios(
//     {
//       url: `https://${process.env.APP_HOST}/order_confirmations/confirm`,
//       method: "POST",
//       data: {
//         order_id,
//         otp,
//       },
//     },
//     { manual: true }
//   );

//   const [{ loading: cancelLoading }, onCancel] = useAxios(
//     {
//       url: `https://${process.env.APP_HOST}/order_confirmations/cancel`,
//       method: "POST",
//       data: {
//         order_id,
//         otp,
//       },
//     },
//     { manual: true }
//   );

//   const onOrderConfirm = () => {
//     onConfirm()
//       .then((resp) => {
//         if (resp.status === 200) {
//           window.location.href = resp.data.order_status_url;
//         } else {
//           setError(true);
//         }
//       })
//       .catch((e) => setError(true));
//   };

//   const onOrderCancel = () => {
//     onCancel()
//       .then((resp) => {
//         if (resp.status === 200) {
//           setCancelled(true);
//         } else {
//           setError(true);
//         }
//       })
//       .catch((e) => setError(true));
//   };

//   useEffect(() => {
//     if (autoVerify) {
//       onOrderConfirm();
//     }
//   }, [autoVerify]);

//   const disableBtns = confirmLoading || cancelLoading || !order || cancelled;

//   if (autoVerify && error) {
//     return (
//       <Banner status="warning">
//         {
//           "Invalid action or link expired - Order is already cancelled or link is expired, Please place new order."
//         }
//       </Banner>
//     );
//   }
//   if (autoVerify) {
//     return <Spinner size="large" />;
//   }
//   return (
//     <div
//       style={{
//         width: "60%",
//         position: "absolute",
//         left: "50%",
//         top: "50%",
//         transform: "translate(-50%, -50%)",
//       }}
//     >
//       <Layout>
//         <Layout.Section>
//           <Card title="Thankyou - Response received from the payment provider for the below Order. Once Payment is confirmed, you will receive an email.">
//             {error && (
//               <div style={{ padding: 10 }}>
//                 <Banner status="warning">
//                   {
//                     "Invalid action or link expired - Order is already cancelled or link is expired, Please place new order."
//                   }
//                 </Banner>
//               </div>
//             )}
//             {cancelled && (
//               <div style={{ padding: 10 }}>
//                 <Banner status="critical">
//                   {I18n.t("admin.order_cancelled")}
//                 </Banner>
//               </div>
//             )}
//             <Card.Section>
//               <ResourceList
//                 items={[
//                   {
//                     term: "Website",
//                     description: shop.owner_name,
//                   },
//                   {
//                     term: "Order Number",
//                     description: "#" + order.order_number,
//                   },
//                   {
//                     term: "Customer Name",
//                     description: order.customer_name,
//                   },
//                   {
//                     term: "Customer Number",
//                     description: order.customer_number,
//                   },
//                   // {
//                   //   term: 'Amount',
//                   //   description: shop.currency + ' ' + order.order_amount
//                   // }
//                 ]}
//                 renderItem={(item) => {
//                   const { term, description } = item;
//                   return (
//                     <ResourceList.Item>
//                       <Stack>
//                         <Stack.Item fill>{term}</Stack.Item>
//                         <Stack.Item>{description}</Stack.Item>
//                       </Stack>
//                     </ResourceList.Item>
//                   );
//                 }}
//               />
//             </Card.Section>
//             <Card.Section>
//               <div
//                 style={{
//                   display: "flex",
//                   flexDirection: "row",
//                   justifyContent: "space-between",
//                   alignItems: "center",
//                 }}
//               >
//                 <Badge size="large" primary>
//                   You may Close Tab this tab
//                 </Badge>
//               </div>
//             </Card.Section>
//           </Card>
//         </Layout.Section>
//       </Layout>
//     </div>
//   );
// };

// const OrderVerify = (props) => {
//   return (
//     <AppProvider theme={{}} i18n={enTranslations}>
//       <ConfirmButtons
//         shop={props.shop}
//         order={props.order}
//         showCancelButton={props.show_cancel_button}
//         autoVerify={props.auto_verify}
//       />
//     </AppProvider>
//   );
// };

// // // Render component with data
// // document.addEventListener("DOMContentLoaded", () => {
// //   const node = document.getElementById("order-prepaid-react");
// //   const data = JSON.parse(node.getAttribute("data"));
// //   ReactDOM.render(<OrderVerify {...data} />, node);
// // });

// document.addEventListener("DOMContentLoaded", () => {
//   const node = document.getElementById("order-prepaid-react");
//   if (!node) return;
//   const data = JSON.parse(node.getAttribute("data"));
//   const root = createRoot(node);
//   root.render(<OrderVerify {...data} />);
// });

// import React, { useState, useEffect, useContext } from 'react';
// import { Card, Subheading, DescriptionList, Button } from '@shopify/polaris';
// import useClippy from 'use-clippy';
// import I18n from "../i18n-lang";
// import { StoreContext } from "../Context/Store";

// const CopyButton = ({ text, onCopy }) => {
//   const [copied, setCopied] = useState(false)
//   const onCopyHandler = () => {
//     setCopied(true)
//     onCopy()
//   }

//   useEffect(() => {
//     let timeout = ''
//     if (copied) {
//       timeout = setTimeout(() => {
//         setCopied(false)
//       }, 3000);
//     }
//     return () => clearTimeout(timeout)
//   }, [copied, setTimeout, clearTimeout])

//   return (
//     <div style={{display: 'flex', justifyContent: 'space-between'}}>
//       {text}
//       <Button size='slim' onClick={onCopyHandler} disabled={copied}>
//         { copied ? I18n.t('admin.copied') : I18n.t('admin.copy')}
//       </Button>
//     </div>
//   )
// }

// const SmsTemplateHelp = ({ onCopy }) => {
//   const [clipboard, setClipboard] = useClippy();
//   const {
//     templateFocus: [, setTemplateFocus]
//   } = useContext(StoreContext);
//   const onCopyHandler = (text) => () => {
//     setClipboard(text)
//     setTemplateFocus(true)
//   }
//   return (
//     <Card sectioned subdued>
//       <Subheading>
//         {I18n.t("admin.available_variables")}
//       </Subheading>
//       <DescriptionList
//         spacing="tight"
//         items={[
//           {
//             term: "{{otp}}",
//             description: (
//               <CopyButton
//                 text={I18n.t("admin.one_time_pass")}
//                 onCopy={onCopyHandler('{{otp}}') }
//               />
//             )
//           },
//           {
//             term: "{{link}}",
//             description: (
//               <CopyButton
//                 text={I18n.t("admin.link_text")}
//                 onCopy={onCopyHandler('{{link}}') }
//               />
//             )
//           },
//           {
//             term: "{{name}}",
//             description: (
//               <CopyButton
//                 text={I18n.t("admin.customer_first_name")}
//                 onCopy={onCopyHandler('{{name}}') }
//               />
//             )
//           },
//           {
//             term: "{{amount}}",
//             description: (
//               <CopyButton
//                 text={I18n.t("admin.order_total_amount")}
//                 onCopy={onCopyHandler('{{amount}}') }
//               />
//             )
//           },
//           {
//             term: "{{number}}",
//             description: (
//               <CopyButton
//                 text={I18n.t("admin.order_number")}
//                 onCopy={onCopyHandler('{{number}}') }
//               />
//             )
//           },
//         ]}
//       />
//     </Card>
//   )
// }

// export default SmsTemplateHelp

// import React, { useState, forwardRef, useImperativeHandle } from "react";
// import { FormLayout, TextField, Select } from "@shopify/polaris";

// const PaymentOptions = forwardRef((_, ref) => {
//   const [amount, setAmount] = useState("");
//   const [amountType, setAmountType] = useState("percentage");
//   const [errors, setErrors] = useState({});

//   const amountTypeOptions = [
//     { label: "Percentage", value: "percentage" },
//     { label: "Fixed", value: "fixed" },
//   ];

//   // **Validation function**
//   const validateForm = () => {
//     let newErrors = {};
//     if (!amount || isNaN(amount) || Number(amount) <= 0) {
//       newErrors.amount = "Enter a valid amount greater than 0.";
//     }
//     setErrors(newErrors);
//     return Object.keys(newErrors).length === 0;
//   };

//   // This function builds the new partial payment option object
//   const handleSubmit = () => {
//     if (!validateForm()) return null;

//     return {
//       rule_name: "Partial Payment",
//       amount: Number(amount),
//       amount_type: amountType,
//     };
//   };

//   // Expose the handleSubmit method via the ref
//   useImperativeHandle(ref, () => ({
//     submit: handleSubmit,
//   }));

//   return (
//     <div style={{ padding: "16px", maxWidth: "400px", margin: "0 auto" }}>
//       <FormLayout>
//         <TextField
//           type="number"
//           label="Amount"
//           value={amount}
//           onChange={(value) => setAmount(value)}
//           placeholder="Enter amount"
//           error={errors.amount} // ✅ Polaris handles the error display natively
//         />

//         <Select
//           label="Amount Type"
//           options={amountTypeOptions}
//           onChange={(value) => setAmountType(value)}
//           value={amountType}
//         />
//       </FormLayout>
//     </div>
//   );
// });

// export default PaymentOptions;

import React, { useState, forwardRef, useImperativeHandle } from "react";
import { Box, FormLayout, TextField, Select } from "@shopify/polaris";
import I18n from "../../i18n-lang";

const PaymentOptions = forwardRef((_, ref) => {
  const [amount, setAmount] = useState("");
  const [amountType, setAmountType] = useState("percentage");
  const [errors, setErrors] = useState({});

  const amountTypeOptions = [
    { label: I18n.t("payment_options.percentage"), value: "percentage" },
    { label: I18n.t("payment_options.fixed"), value: "fixed" },
  ];

  const validateForm = () => {
    let newErrors = {};
    if (!amount || isNaN(amount) || Number(amount) <= 0) {
      newErrors.amount = "Enter a valid amount greater than 0.";
    }
    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = () => {
    if (!validateForm()) return null;

    return {
      rule_name: "Partial Payment",
      amount: Number(amount),
      amount_type: amountType,
    };
  };

  useImperativeHandle(ref, () => ({
    submit: handleSubmit,
  }));

  return (
    <Box padding="400" maxWidth="400px" margin="0 auto">
      <FormLayout>
        <TextField
          type="number"
          label={I18n.t("payment_options.amount")}
          value={amount}
          onChange={(value) => setAmount(value)}
          autoComplete="off"
          placeholder={I18n.t("payment_options.enter_amount")}
          error={errors.amount}
        />

        <Select
          label={I18n.t("payment_options.amount_type")}
          options={amountTypeOptions}
          onChange={(value) => setAmountType(value)}
          value={amountType}
        />
      </FormLayout>
    </Box>
  );
});

export default PaymentOptions;

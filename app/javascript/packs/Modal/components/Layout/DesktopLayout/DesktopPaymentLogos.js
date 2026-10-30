import React from "react";
import styled from "styled-components";
// PaymentLogos Component
const PaymentLogosComponent = () => (
  <StyledPaymentLogos>
    {/* {["visa", "mastercard", "rupay", "upi", "netbanking"].map((method) => (
      <PaymentLogo
        key={method}
        src={`/placeholder.svg?height=24&width=40`}
        alt={method}
      />
    ))} */}
  </StyledPaymentLogos>
);
export default PaymentLogosComponent;
// StyledPaymentLogos
const StyledPaymentLogos = styled.div`
  margin-top: 24px;
  display: flex;
  justify-content: center;
  gap: 16px;
`;

const PaymentLogo = styled.img`
  height: 24px;
  object-fit: contain;
`;

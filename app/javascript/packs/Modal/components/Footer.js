import React from "react";
import styled from "styled-components";
import useOtpStore from "../stores/otpStore";
import { getSessionValue } from "../utilities/otpUtils";

const SecuredSection = styled.div`
  margin-top: auto;
  text-align: center;
`;

const IllustrationPlaceholder = styled.div`
  margin-bottom: 16px;
  height: 100px;
`;

const SecuredText = styled.div`
  font-size: 12px;
  opacity: 0.8;
`;

const PaymentLogos = styled.div`
  margin-top: 24px;
  display: flex;
  justify-content: center;
  gap: 16px;
`;

const PaymentLogo = styled.img`
  height: 24px;
  object-fit: contain;
`;

export default function Footer() {
  const { otpData } = useOtpStore();
  const { codkingTrusted, codking } = otpData;
  const settings = getSessionValue("settingSession");
  const { preShowBranding } = settings;
  return (
    <SecuredSection>
      <IllustrationPlaceholder />
      {preShowBranding ? <SecuredText>Secured by {codking}</SecuredText> : ""}

      <PaymentLogos>
        {/* {["visa", "mastercard", "rupay", "upi", "netbanking"].map((method) => (
          <PaymentLogo
            key={method}
            src={`/placeholder.svg?height=24&width=40`}
            alt={method}
          />
        ))} */}
      </PaymentLogos>
    </SecuredSection>
  );
}

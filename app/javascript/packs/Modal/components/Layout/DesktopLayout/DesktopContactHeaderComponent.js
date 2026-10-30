import React from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";

// ContactHeader Component
const ContactHeaderComponent = ({ theme }) => {
  const { settings } = useOtpStore();
  const { heading, subHeading } = settings;

  return (
    <StyledContactHeaderCODK>
      {/* <ContactIconCODK>
        <svg
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        >
          <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
          <circle cx="12" cy="7" r="4" />
        </svg>
      </ContactIconCODK> */}
      <div>
        <ContactTitleCODK>
          {settings?.preIsLoginEnabled
            ? "Customer login"
            : heading || "Contact details"}
        </ContactTitleCODK>

        <ContactSubtitleCODK>
          {subHeading || "Enter mobile to continue"}
        </ContactSubtitleCODK>
      </div>
    </StyledContactHeaderCODK>
  );
};

export default ContactHeaderComponent;

// Styled Components
const StyledContactHeaderCODK = styled.div`
  gap: 16px !important;
  margin-bottom: 24px !important;

  @media (max-width: 767px) {
    // background-image: url("https://cdn.shopify.com/s/files/1/0743/3119/3628/files/rings.svg?v=1750424363"),
    //   linear-gradient(
    //     to bottom right,
    //     ${(props) => props.theme.secondary},
    //     ${(props) => props.theme.cardBg}
    //   ) !important;

    background-repeat: no-repeat, no-repeat !important;
    background-position: top 20px left 20px, center !important;
    background-size: 180px, cover !important;

    max-height: 200px !important;
    overflow-y: auto !important;
    -webkit-overflow-scrolling: touch !important;
    position: relative !important;
    z-index: 0 !important;
  }
`;

const ContactIconCODK = styled.div`
  width: 32px !important;
  height: 32px !important;
  border-radius: 50% !important;
  border: 1px solid ${(props) => props.theme.border} !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  margin-bottom: 20px !important;
`;

const ContactTitleCODK = styled.div`
  font-size: 20px !important;
  line-height: 28px !important;
  font-weight: 600 !important;
  --tw-text-opacity: 1;

  @media (max-width: 768px) {
    font-size: 20px !important;
    line-height: 28px !important;
    font-weight: 599 !important;
  }
`;

const ContactSubtitleCODK = styled.div`
  // line-height: 17.5px !important;
  margin: 4px 0 0 !important;
  color: #666 !important;
  font-size: 14px !important;
`;

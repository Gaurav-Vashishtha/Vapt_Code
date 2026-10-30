import React from "react";
import styled from "styled-components";

// Styled Components
const StyledContactHeaderCODK = styled.div`
  display: flex !important;
  align-items: center !important;
  gap: 16px !important;
  margin-bottom: 24px !important;
  margin-top: 50px !important;
`;

const ContactIconCODK = styled.div`
  width: 32px !important;
  height: 32px !important;
  border-radius: 50% !important;
  border: 1px solid ${(props) => props.theme.border} !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
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
  margin: 4px 0 0 !important;
  color: #666 !important;
  font-size: 14px !important;
`;

// ContactHeader Component
const EmailHeaderComponent = ({ theme }) => (
  <StyledContactHeaderCODK>
    <ContactIconCODK>
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
    </ContactIconCODK>
    <div>
      <ContactTitleCODK>Email details</ContactTitleCODK>
      <ContactSubtitleCODK>Enter email to continue</ContactSubtitleCODK>
    </div>
  </StyledContactHeaderCODK>
);

export default EmailHeaderComponent;

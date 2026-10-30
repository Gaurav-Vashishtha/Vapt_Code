import React from "react";
import styled from "styled-components";
import { Shield, Truck, CreditCard } from "lucide-react";

import useOtpStore from "../../../stores/otpStore";
import { getSessionValue } from "../../../utilities/otpUtils";

export default function DesktopFooter({ theme }) {
  const settings = getSessionValue("settingSession");
  const { preShowBranding } = settings;

  return (
    <FooterContainerCODK theme={theme}>
      {/* Top row: icons + labels */}
      <IconsRowCODK>
        <IconItemCODK>
          <IconWrapperCODK>
            <CreditCard size={16} />
          </IconWrapperCODK>
          <IconLabelCODK>Secure payments</IconLabelCODK>
        </IconItemCODK>

        <IconItemCODK>
          <IconWrapperCODK>
            <Truck size={16} />
          </IconWrapperCODK>
          <IconLabelCODK>Assured delivery</IconLabelCODK>
        </IconItemCODK>

        <IconItemCODK>
          <IconWrapperCODK>
            <Shield size={16} />
          </IconWrapperCODK>
          <IconLabelCODK>Verified seller</IconLabelCODK>
        </IconItemCODK>
      </IconsRowCODK>

      {/* Bottom row: links + Subtle Attribution */}
      <BottomRowCODK>
        <FooterLinksCODK>
          <a
            href="https://codking.notion.site/Terms-and-Conditions-COD-King-1a96e71a63f980358f6fe23c3c96485c"
            target="_blank"
            rel="noopener noreferrer"
          >
            T&C
          </a>
          <DividerCODK>|</DividerCODK>
          <a
            href="https://codking.notion.site/Privacy-Policy-COD-King-1ab6e71a63f980fb882df2e6a7173576"
            target="_blank"
            rel="noopener noreferrer"
          >
            Privacy Policy
          </a>
        </FooterLinksCODK>

        {preShowBranding && (
          <SubtleAttribution>
            <TinyLogo src="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/CK_logo_icon-1200px.png?v=1757062726" />
            COD King
          </SubtleAttribution>
        )}
      </BottomRowCODK>
    </FooterContainerCODK>
  );
}

/* --- STYLES --- */

const SubtleAttribution = styled.div`
  display: flex !important;
  align-items: center !important;
  gap: 4px !important;
  font-size: 10px !important;
  color: #9ca3af !important;
  opacity: 0.8;
`;

const TinyLogo = styled.img`
  width: 14px !important;
  height: 14px !important;
  filter: grayscale(100%);
  opacity: 0.6;
`;

const FooterContainerCODK = styled.div`
  background-color: transparent !important;
  /* a subtle light color to match typical screenshot backgrounds */
  //   padding: 9px 3px;
  //   border-top: 1px solid ${(props) => props.theme.border};
  display: flex !important;
  flex-direction: column !important;
  gap: 20px !important;
  // width: 95%;
`;

const IconsRowCODK = styled.div`
  display: flex !important;
  justify-content: center !important;
  align-items: flex-start !important;
  gap: 20px !important; /* Larger gap for a more spacious look */
  flex-wrap: wrap !important;
`;

const IconItemCODK = styled.div`
  display: flex !important;
  flex-direction: column !important;
  align-items: center !important;
  text-align: center !important;
`;

const IconWrapperCODK = styled.div`
  font-size: 20px !important;
  color: #666 !important;
`;

const IconLabelCODK = styled.span`
  font-size: 10px !important;
  color: #444 !important;
  font-weight: 500 !important;
`;

const BottomRowCODK = styled.div`
  display: flex !important;
  flex-wrap: wrap !important;
  justify-content: space-between !important;
  // width: 95%;
  gap: 16px !important;
`;

const FooterLinksCODK = styled.div`
  display: flex !important;
  align-items: center !important;
  gap: 8px !important;

  a {
    text-decoration: none !important;
    color: ${(props) => props.theme.text} !important;
    font-size: 10px !important;
  }

  span {
    font-size: 10px !important;
    color: #666 !important;
  }
`;

const DividerCODK = styled.span`
  color: #bbb !important;
  font-size: 14px !important;
`;

import React, { useEffect, useState } from "react";
import styled from "styled-components";
import useOtpStore from "../../../stores/otpStore";
import {
  checkImageAspectRatio,
  getSessionValue,
} from "../../../utilities/otpUtils";

const MobileHeaderTop = ({ theme, onClose }) => {
  const { otpData } = useOtpStore();
  const settings = getSessionValue("settingSession");
  const { preV2Title, brandLogoUrl } = settings;
  const [imageType, setImageType] = useState(null);

  function formatTitle(str, maxLen = 20) {
    if (!str) return "";
    const titleCase = str
      .toLowerCase()
      .split(" ")
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
      .join(" ");
    return titleCase.length > maxLen
      ? titleCase.slice(0, maxLen - 3) + "..."
      : titleCase;
  }

  useEffect(() => {
    if (brandLogoUrl) {
      checkImageAspectRatio(brandLogoUrl)
        .then((result) => setImageType(result))
        .catch((error) => console.error(error));
    }
  }, [brandLogoUrl]);

  return (
    <HeaderTop theme={theme}>
      <StyledCompanyHeader>
        {/* Show default logo only if image is square or no image is available */}
        {!brandLogoUrl || imageType === "Square image" ? (
          <CompanyLogoCODK>
            {brandLogoUrl ? (
              <img src={brandLogoUrl} alt="Brand Logo" />
            ) : (
              <DefaultLogoCODK>{preV2Title?.charAt(0) || ""}</DefaultLogoCODK>
            )}
          </CompanyLogoCODK>
        ) : null}

        {/* Show wide logo or company name */}
        <CompanyName>
          {imageType === "Wide image" ? (
            <WideLogo src={brandLogoUrl} alt="Brand Logo" />
          ) : (
            formatTitle(preV2Title, 30)
          )}
        </CompanyName>
      </StyledCompanyHeader>
      <ActionButton />
      <CloseButton onClick={onClose}>×</CloseButton>
    </HeaderTop>
  );
};

export default MobileHeaderTop;

// Styled Components
const HeaderTop = styled.div`
  position: relative !important;
  display: flex !important;
  align-items: center !important;
  justify-content: space-between !important;
  background-color: ${(props) => props.theme.primaryDark} !important;
  padding: 4px 16px !important;
  min-height: 60px !important;
`;

const StyledCompanyHeader = styled.div`
  display: flex !important;
  align-items: center !important;
  gap: 12px !important;
  background: transparent !important;
  padding: 10px 0 !important;
`;

const CompanyLogoCODK = styled.div`
  width: 40px !important;
  height: 40px !important;
  background: rgba(255, 255, 255, 0.9) !important;
  border-radius: 8px !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  overflow: hidden !important;
  border: 1px solid rgba(255, 255, 255, 0.2) !important;
  backdrop-filter: blur(4px) !important;

  img {
    width: 100% !important;
    height: 100% !important;
    object-fit: contain !important;
    border-radius: 6px !important;
  }
`;

const DefaultLogoCODK = styled.div`
  font-size: 20px !important;
  font-weight: bold !important;
  color: #333 !important;
`;

const CompanyName = styled.div`
  font-weight: bold !important;
  font-size: 16px !important;
  color: white !important;
  text-transform: capitalize !important;
  display: flex !important;
  align-items: center !important;
`;

const WideLogo = styled.img`
  max-height: 30px !important;
  max-width: 200px !important;
  object-fit: contain !important;
  border-radius: 4px !important;
  background: rgba(255, 255, 255, 0.9) !important;
  padding: 4px 8px !important;
  backdrop-filter: blur(4px) !important;
`;

const ActionButton = styled.button`
  background: transparent !important;
  border: none !important;
  color: #fff !important;
  border-radius: 8px !important;
  width: 40px !important;
  height: 40px !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  font-size: 18px !important;
`;

const CloseButton = styled.button`
  position: absolute !important;
  top: 12px !important;
  right: 16px !important;
  background: transparent !important;
  border: none !important;
  font-size: 26px !important;
  cursor: pointer !important;
  color: rgba(255, 255, 255, 0.7) !important;
  transition: color 0.2s ease, transform 0.2s ease !important;

  &:hover {
    color: white !important;
    transform: scale(1.1) !important;
  }
`;

// import React, { useState, useContext } from "react";
// import styled from "styled-components";
// import { Clock } from "lucide-react";
// import { StoreContext } from "../Context/Store";
// import I18n from "../i18n-lang";
// import { navigateTo } from "../../utils/navigate";

// const CardWrapper = styled.div`
//   border-radius: 12px;
//   border: 1px solid #e5e7eb;
//   padding: 24px 16px;
//   display: flex;
//   flex-direction: column;
//   justify-content: space-between;
//   position: relative;
//   box-shadow: 0 1px 4px rgba(0, 0, 0, 0.05);
//   background: white;
//   height: 100%;
// `;

// const Heading = styled.h2`
//   font-size: 16px;
//   font-weight: 700;
//   color: #1f2937;
//   margin-bottom: 8px;
//   text-align: center;
// `;

// const Subheading = styled.p`
//   font-size: 13px;
//   color: #6b7280;
//   margin-bottom: 10px;
//   line-height: 1.4;
//   text-align: center;
// `;

// const Footer = styled.div`
//   margin-top: auto;
//   display: flex;
//   justify-content: space-between;
//   align-items: center;
//   padding-top: 12px;
//   border-top: 1px solid #f3f4f6;
// `;

// const ButtonWrapper = styled.button`
//   background-color: #16a34a;
//   color: white;
//   padding: 8px 16px;
//   border-radius: 6px;
//   font-size: 13px;
//   cursor: pointer;
//   border: none;
//   font-weight: 500;
// `;

// const WatchLinkTop = styled.span`
//   position: absolute;
//   top: 12px;
//   right: 12px;
//   color: #3b82f6;
//   font-size: 12px;
//   cursor: pointer;
//   text-decoration: underline;
// `;

// const VideoOverlay = styled.div`
//   position: fixed;
//   top: 0;
//   left: 0;
//   width: 100%;
//   height: 100%;
//   background: rgba(0, 0, 0, 0.8);
//   display: flex;
//   justify-content: center;
//   align-items: center;
//   z-index: 1000;
// `;

// const VideoWrapper = styled.div`
//   position: relative;
//   width: 90%;
//   max-width: 600px;
//   iframe {
//     width: 100%;
//     height: 350px;
//   }
// `;

// const CloseButton = styled.button`
//   position: absolute;
//   top: -10px;
//   right: -10px;
//   background: #fff;
//   border: none;
//   border-radius: 50%;
//   width: 22px;
//   height: 22px;
//   cursor: pointer;
// `;

// const Illustration = styled.img`
//   width: 90px;
//   height: 90px;
//   object-fit: contain;
//   margin: 12px auto;
// `;

// const SalesCard = ({
//   imageSrc,
//   heading,
//   subheading,
//   setupTime,
//   ctaText,
//   videoLink,
//   navigateToPath,
// }) => {
//   const [showVideo, setShowVideo] = useState(false);

//   return (
//     <CardWrapper>
//       {videoLink?.length > 0 && (
//         <WatchLinkTop onClick={() => setShowVideo(true)}>
//           {I18n.t("onboarding.watch_video")}
//         </WatchLinkTop>
//       )}
//       <Illustration src={imageSrc} alt="icon" />
//       <div>
//         <Heading>{heading}</Heading>
//         <Subheading>{subheading}</Subheading>
//       </div>
//       <Footer>
//         <div
//           style={{
//             display: "flex",
//             alignItems: "center",
//             fontSize: "11px",
//             color: "#6b7280",
//           }}
//         >
//           <Clock size={11} style={{ marginRight: "4px" }} />
//           {setupTime}
//         </div>
//         <ButtonWrapper onClick={navigateToPath}>
//           {ctaText}
//         </ButtonWrapper>
//       </Footer>
//       {showVideo && (
//         <VideoOverlay>
//           <VideoWrapper>
//             <CloseButton onClick={() => setShowVideo(false)}>×</CloseButton>
//             <iframe
//               src={videoLink}
//               frameBorder="0"
//               allow="autoplay; encrypted-media"
//               allowFullScreen
//               title="video"
//             ></iframe>
//           </VideoWrapper>
//         </VideoOverlay>
//       )}
//     </CardWrapper>
//   );
// };

// const Container = styled.div`
//   background: #f9fafb;
//   padding: 16px;
//   max-width: 1600px;
//   margin: auto;
//   padding-left: 100px;
//   padding-right: 100px;

//   @media (max-width: 1280px) {
//     padding-left: 40px;
//     padding-right: 40px;
//   }

//   @media (max-width: 768px) {
//     padding-left: 16px;
//     padding-right: 16px;
//   }
// `;

// const CardsGrid = styled.div`
//   display: grid;
//   grid-template-columns: repeat(3, 1fr);
//   gap: 20px;
//   align-items: stretch;

//   @media (max-width: 1280px) {
//     grid-template-columns: repeat(3, 1fr);
//   }
//   @media (max-width: 768px) {
//     grid-template-columns: repeat(2, 1fr);
//   }
//   @media (max-width: 480px) {
//     grid-template-columns: 1fr;
//   }
// `;

// export default function Onboarding() {
//   const { isPrepaidEnabled } = useContext(StoreContext);

//   return (
//     <Container>
//       <CardsGrid>
//         <SalesCard
//           imageSrc="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/secure-shield.png?v=1742311946"
//           heading={I18n.t("onboarding.phone_heading")}
//           subheading={I18n.t("onboarding.phone_subheading")}
//           setupTime={I18n.t("onboarding.setup_2min")}
//           ctaText={I18n.t("onboarding.setup_otp")}
//           videoLink="https://www.youtube.com/embed/DyzY_6S8724"
//           navigateToPath={() => navigateTo("/features/otp")}
//         />
//         <SalesCard
//           imageSrc="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/cash-on-delivery_ab4e4cbc-5c7f-4549-a125-e86b0dbf087a.png?v=1742379790"
//           heading={I18n.t("onboarding.cod_heading")}
//           subheading={I18n.t("onboarding.cod_subheading")}
//           setupTime={I18n.t("onboarding.setup_1min")}
//           ctaText={I18n.t("onboarding.setup_cod")}
//           videoLink="https://www.youtube.com/embed/I22U3fj6vKo"
//           navigateToPath={() => navigateTo("/features/cod-fees")}
//         />
//         <SalesCard
//           imageSrc="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/unread-massage-chat.png?v=1742311946"
//           heading={I18n.t("onboarding.notifications_heading")}
//           subheading={I18n.t("onboarding.notifications_subheading")}
//           setupTime={I18n.t("onboarding.setup_1min")}
//           ctaText={I18n.t("onboarding.setup_sms")}
//           videoLink=""
//           navigateToPath={() => navigateTo("/features/notifications")}
//         />
//         <SalesCard
//           imageSrc="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/3878347.webp?v=1742384083"
//           heading={I18n.t("onboarding.rules_heading")}
//           subheading={I18n.t("onboarding.rules_subheading")}
//           setupTime={I18n.t("onboarding.setup_1min")}
//           ctaText={I18n.t("onboarding.setup_rules")}
//           videoLink=""
//           navigateToPath={() => navigateTo("/features/cod-show-hide")}
//         />
//         <SalesCard
//           imageSrc="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/coin-in-hand.png?v=1742379790"
//           heading={I18n.t("onboarding.partial_heading")}
//           subheading={I18n.t("onboarding.partial_subheading")}
//           setupTime={I18n.t("onboarding.setup_2min")}
//           ctaText={I18n.t("onboarding.setup_partial")}
//           videoLink=""
//           navigateToPath={() => navigateTo("/features/partial-payment")}
//         />
//         <SalesCard
//           imageSrc="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/shopping-cart.png?v=1742311946"
//           heading={I18n.t("onboarding.recovery_heading")}
//           subheading={I18n.t("onboarding.recovery_subheading")}
//           setupTime={I18n.t("onboarding.setup_2min")}
//           ctaText={I18n.t("onboarding.setup_recovery")}
//           videoLink="https://www.youtube.com/embed/OIYtQF4ZRHQ"
//           navigateToPath={() => navigateTo("/features/notifications")}
//         />
//         {isPrepaidEnabled && (
//           <SalesCard
//             imageSrc="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/credit-card.png?v=1742383835"
//             heading={I18n.t("onboarding.convert_heading")}
//             subheading={I18n.t("onboarding.convert_subheading")}
//             setupTime={I18n.t("onboarding.setup_3min")}
//             ctaText={I18n.t("onboarding.setup_convert")}
//             videoLink=""
//             navigateToPath={() => navigateTo("/features/cod-to-prepaid")}
//           />
//         )}
//       </CardsGrid>
//     </Container>
//   );
// }
import React, { useState, useContext } from "react";
import {
  Card,
  BlockStack,
  InlineStack,
  Text,
  Button,
  Modal,
  Icon,
  Box,
  Page,
  Badge,
} from "@shopify/polaris";
import { Clock } from "lucide-react";
import { StoreContext } from "../Context/Store";
import I18n from "../i18n-lang";
import { navigateTo } from "../../utils/navigate";

function SalesCard({
  imageSrc,
  heading,
  subheading,
  setupTime,
  ctaText,
  videoLink,
  navigateToPath,
  isPro = false,
}) {
  const [showVideo, setShowVideo] = useState(false);

  return (
    <>
      <Card padding="400" rounded>
        <BlockStack gap="200" align="center">
          {/* Top watch video link */}
          {videoLink?.length > 0 && (
            <Box position="absolute" top="0" right="0" padding="200">
              <Text
                as="span"
                variant="bodySm"
                tone="accent"
                fontWeight="medium"
                underline
                style={{ cursor: "pointer" }}
                onClick={() => setShowVideo(true)}
              >
                {I18n.t("onboarding.watch_video")}
              </Text>
            </Box>
          )}
          <Box>
            <img
              src={imageSrc}
              alt={I18n.t("onboarding.feature_illustration")}
              width={90}
              height={90}
              style={{
                display: "block",
                margin: "12px auto",
                objectFit: "contain",
                borderRadius: 8,
              }}
            />
          </Box>
          <Text as="h2" variant="headingSm" alignment="center">
            {heading}
          </Text>
          <Text as="p" variant="bodySm" tone="subdued" alignment="center">
            {subheading}
          </Text>
          <InlineStack gap="200" align="space-between" width="100%">
            <InlineStack gap="100" align="center">
              <Icon source={Clock} tone="subdued" />
              <Text as="span" variant="bodyXs" tone="subdued">
                {setupTime}
              </Text>
            </InlineStack>
            <Button variant="primary" size="medium" onClick={navigateToPath}>
              {ctaText}
            </Button>
          </InlineStack>
        </BlockStack>
      </Card>

      {/* Video Modal */}
      <Modal
        open={showVideo}
        onClose={() => setShowVideo(false)}
        title={I18n.t("onboarding.watch_video")}
        large
      >
        <Modal.Section>
          <Box width="100%" style={{ aspectRatio: "16/9" }}>
            <iframe
              src={videoLink}
              frameBorder="0"
              allow="autoplay; encrypted-media"
              allowFullScreen
              title={I18n.t("onboarding.video")}
              width="100%"
              height="350"
              style={{ borderRadius: 8, width: "100%" }}
            ></iframe>
          </Box>
        </Modal.Section>
      </Modal>
    </>
  );
}

export default function Onboarding() {
  const { isPrepaidEnabled } = useContext(StoreContext);

  // Responsive grid with InlineStack wrap and Box for outer spacing
  const cards = [
    {
      imageSrc:
        "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/secure-shield.png?v=1742311946",
      heading: I18n.t("onboarding.phone_heading"),
      subheading: I18n.t("onboarding.phone_subheading"),
      setupTime: I18n.t("onboarding.setup_2min"),
      ctaText: I18n.t("onboarding.setup_otp"),
      videoLink: "https://www.youtube.com/embed/yCPBjrO2tFA",
      navigateToPath: () => navigateTo("/features/otp/pre-order"),
    },
    {
      imageSrc:
        "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/cash-on-delivery_ab4e4cbc-5c7f-4549-a125-e86b0dbf087a.png?v=1742379790",
      heading: I18n.t("onboarding.cod_heading"),
      subheading: I18n.t("onboarding.cod_subheading"),
      setupTime: I18n.t("onboarding.setup_1min"),
      ctaText: I18n.t("onboarding.setup_cod"),
      videoLink: "https://www.youtube.com/embed/I22U3fj6vKo",
      navigateToPath: () => navigateTo("/features/cod-fees"),
      isPro: true,
    },
    {
      imageSrc:
        "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/unread-massage-chat.png?v=1742311946",
      heading: I18n.t("onboarding.notifications_heading"),
      subheading: I18n.t("onboarding.notifications_subheading"),
      setupTime: I18n.t("onboarding.setup_1min"),
      ctaText: I18n.t("onboarding.setup_sms"),
      videoLink: "",
      navigateToPath: () => navigateTo("/features/notifications"),
    },
    {
      imageSrc:
        "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/3878347.webp?v=1742384083",
      heading: I18n.t("onboarding.rules_heading"),
      subheading: I18n.t("onboarding.rules_subheading"),
      setupTime: I18n.t("onboarding.setup_1min"),
      ctaText: I18n.t("onboarding.setup_rules"),
      videoLink: "",
      navigateToPath: () => navigateTo("/features/limit-cod"),
      isPro: true,
    },
    {
      imageSrc:
        "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/coin-in-hand.png?v=1742379790",
      heading: I18n.t("onboarding.partial_heading"),
      subheading: I18n.t("onboarding.partial_subheading"),
      setupTime: I18n.t("onboarding.setup_2min"),
      ctaText: I18n.t("onboarding.setup_partial"),
      videoLink: "",
      navigateToPath: () => navigateTo("/features/partial-payment"),
    },
    {
      imageSrc:
        "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/shopping-cart.png?v=1742311946",
      heading: I18n.t("onboarding.recovery_heading"),
      subheading: I18n.t("onboarding.recovery_subheading"),
      setupTime: I18n.t("onboarding.setup_2min"),
      ctaText: I18n.t("onboarding.setup_recovery"),
      videoLink: "https://www.youtube.com/embed/OIYtQF4ZRHQ",
      navigateToPath: () => navigateTo("/features/notifications"),
    },
    ...(isPrepaidEnabled
      ? [
          // {
          //   imageSrc:
          //     "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/credit-card.png?v=1742383835",
          //   heading: I18n.t("onboarding.convert_heading"),
          //   subheading: I18n.t("onboarding.convert_subheading"),
          //   setupTime: I18n.t("onboarding.setup_3min"),
          //   ctaText: I18n.t("onboarding.setup_convert"),
          //   videoLink: "",
          //   navigateToPath: () => navigateTo("/features/cod-to-prepaid"),
          // },
        ]
      : []),
  ];

  return (
    <Page
      backAction={{
        content: I18n.t("onboarding.back_to_summary"),
        onAction: () => navigateTo("/"),
      }}
    >
      <Box
        background="bg-surface-secondary"
        paddingBlock="400"
        paddingInline="600"
        maxWidth="1600px"
        marginInline="auto"
      >
        <BlockStack gap="400">
          <InlineStack gap="400" wrap align="start">
            {cards.map((props, idx) => (
              <Box
                key={idx}
                width="100%"
                minWidth="280px"
                maxWidth="390px"
                flex="1 1 0"
              >
                <SalesCard {...props} />
              </Box>
            ))}
          </InlineStack>
        </BlockStack>
      </Box>
    </Page>
  );
}

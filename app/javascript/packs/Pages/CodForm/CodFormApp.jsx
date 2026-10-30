import React from "react";
import { Box, Card, Page, SkeletonBodyText, SkeletonDisplayText, BlockStack } from "@shopify/polaris";
import useCodFormBootstrap from "./useCodFormBootstrap";
import { BASE_PATH } from "./constants";
import { OFFER_SEGMENTS } from "./Offers/offerMeta";
import ModuleDisabled from "./components/ModuleDisabled";
import SetupPage from "./Setup/SetupPage";
import AdvancedSettingsPage from "./Setup/AdvancedSettingsPage";
import ButtonsPage from "./Buttons/ButtonsPage";
import DesignerRoute from "./Designer/DesignerRoute";
import DesignerPage from "./Designer/DesignerPage";
import FormsListPage from "./Designer/FormsListPage";
import ShippingPage from "./Shipping/ShippingPage";
import FraudPage from "./Fraud/FraudPage";
import OffersPage from "./Offers/OffersPage";
import OffersListPage from "./Offers/OffersListPage";
import QuantityOfferEditor from "./Offers/QuantityOfferEditor";
import BumpEditor from "./Offers/BumpEditor";
import UpsellEditor from "./Offers/UpsellEditor";
import PreUpsellEditor from "./Offers/PreUpsellEditor";
import BundleEditor from "./Offers/BundleEditor";
import DownsellEditor from "./Offers/DownsellEditor";
import ThresholdEditor from "./Offers/ThresholdEditor";
import AbTestsPage from "./Offers/AbTestsPage";
import AbTestEditor from "./Offers/AbTestEditor";
import CodFormAnalytics from "./Analytics/CodFormAnalytics";

const EDITORS = {
  quantity: QuantityOfferEditor,
  bumps: BumpEditor,
  "pre-upsells": PreUpsellEditor,
  bundles: BundleEditor,
  upsells: UpsellEditor,
  downsells: DownsellEditor,
  thresholds: ThresholdEditor,
};

const Loading = () => (
  <Page fullWidth>
    <Card>
      <Box padding="200">
        <BlockStack gap="400">
          <SkeletonDisplayText size="small" />
          <SkeletonBodyText lines={6} />
        </BlockStack>
      </Box>
    </Card>
  </Page>
);

/**
 * Entry of the COD Form admin module. `path` is the app route without the
 * /settings-hub prefix (Home.jsx passes normalizedLocation). The screen
 * switch follows ARCHITECTURE H.4.
 */
const CodFormApp = ({ path }) => {
  const bootstrap = useCodFormBootstrap();
  if (!bootstrap) return <Loading />;
  if (!bootstrap.moduleEnabled) return <ModuleDisabled />;

  const rest = String(path || BASE_PATH).slice(BASE_PATH.length).replace(/^\/+|\/+$/g, "");
  const [section, second, third] = rest.split("/");

  switch (section || "") {
    case "":
      return <SetupPage />;
    case "advanced":
      return <AdvancedSettingsPage />;
    case "buttons":
      return <ButtonsPage />;
    case "designer":
      if (!second) return <DesignerRoute />;
      if (second === "forms") return <FormsListPage />;
      return <DesignerPage key={second} formId={second} showFormsLink />;
    case "shipping":
      return <ShippingPage />;
    case "fraud":
      return <FraudPage />;
    case "analytics":
      return <CodFormAnalytics />;
    case "offers": {
      if (!second) return <OffersPage />;
      if (second === "ab-tests") {
        return third ? <AbTestEditor key={third} id={third} /> : <AbTestsPage />;
      }
      if (OFFER_SEGMENTS.includes(second)) {
        if (!third) return <OffersListPage key={second} segment={second} />;
        const Editor = EDITORS[second];
        return <Editor key={`${second}-${third}`} segment={second} id={third} />;
      }
      return <OffersPage />;
    }
    default:
      return <SetupPage />;
  }
};

export default CodFormApp;

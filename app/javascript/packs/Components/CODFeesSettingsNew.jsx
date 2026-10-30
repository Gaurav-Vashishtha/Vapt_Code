// import React, {
//   useContext,
//   useRef,
//   useEffect,
//   useCallback,
//   useState,
// } from "react";
// import {
//   Page,
//   Layout,
//   Card,
//   Form,
//   Select,
//   TextField,
//   Checkbox,
//   Banner,
//   Text,
//   List,
//   Link,
//   Button,
// //   VideoThumbnail,
// } from "@shopify/polaris";
// import { StoreContext } from "../Context/Store";
// import useApi from "../Hooks/useApi";
// import Api from "../Services/Api";
// import I18n from "../i18n-lang";
// import { navigateTo } from "../../utils/navigate";
// import { ContextualSaveBar as AppBridgeSaveBar } from "@shopify/app-bridge/actions";
// import { debugLog } from "../Modal/utilities/otpUtils";
// import { Redirect } from "@shopify/app-bridge/actions";
// export default function CODFeesSettingsLayout() {
//   const {
//     loading: [loading, setLoading],
//     plan: [plan],
//     shop: [shop],
//     setting: [setting, setSetting],
//     originalSetting: [originalSetting, setOriginalSetting],
//     tab: [tab, setTab],
//     isPrepaidEnabled,
//   } = useContext(StoreContext);

//   const [contextualBar, setContextualBar] = useState(false);
//   const [isDirty, setIsDirty] = useState(false);
//   const prepaidTabIncrement = isPrepaidEnabled ? 1 : 0;
//   const settingRef = useRef(setting);
//   const saveBarRef = useRef(null);

//   const [{ data: paymentMethods }, getPaymentMethods] = useApi(
//     {
//       url: `https://${process.env.APP_HOST}/settings/payment_methods`,
//       method: "GET",
//     },
//     { manual: true }
//   );

//   useEffect(() => {
//     if (!paymentMethods) getPaymentMethods();
//   }, [paymentMethods, getPaymentMethods]);

//   useEffect(() => {
//     settingRef.current = setting;
//   }, [setting]);

//   const resetLocalStates = useCallback(() => {
//     setIsDirty(false);
//     setContextualBar(false);
//   }, []);

//   const handleSubmit = useCallback(() => {
//     setLoading(true);
//     Api.post("/settings", settingRef.current)
//       .then((res) => {
//         setSetting(res.data);
//         setOriginalSetting(res.data);
//         resetLocalStates();
//       })
//       .catch((err) => {
//         debugLog(err);
//         setContextualBar(false);
//       })
//       .finally(() => setLoading(false));
//   }, [setLoading, setSetting, setOriginalSetting, resetLocalStates]);

//   const handleSettingChange = useCallback(
//     (key) => (value) => {
//       setSetting((prev) => ({ ...prev, [key]: value }));
//       setIsDirty(true);
//       setContextualBar(true);
//     },
//     [setSetting]
//   );

//   useEffect(() => {
//     if (!window.app || saveBarRef.current) return;
//     saveBarRef.current = AppBridgeSaveBar.create(window.app, {
//       message: I18n.t("admin.unsaved"),
//       saveAction: { content: I18n.t("admin.save") },
//       discardAction: { content: I18n.t("admin.discard") },
//     });
//     saveBarRef.current.subscribe(AppBridgeSaveBar.Action.SAVE, async () => {
//       await handleSubmit();
//       saveBarRef.current.dispatch(AppBridgeSaveBar.Action.HIDE);
//     });
//     saveBarRef.current.subscribe(AppBridgeSaveBar.Action.DISCARD, () => {
//       setSetting(JSON.parse(JSON.stringify(originalSetting)));
//       resetLocalStates();
//       saveBarRef.current.dispatch(AppBridgeSaveBar.Action.HIDE);
//     });
//   }, [handleSubmit, resetLocalStates, setSetting, originalSetting]);

//   useEffect(() => {
//     if (!saveBarRef.current) return;
//     contextualBar
//       ? saveBarRef.current.dispatch(AppBridgeSaveBar.Action.SHOW)
//       : saveBarRef.current.dispatch(AppBridgeSaveBar.Action.HIDE);
//   }, [contextualBar]);

//   const renderBanner = () => {
//     if (
//       !setting.locked &&
//       setting.enableShippingCodFees &&
//       (plan.name === "Free" || !shop.charge_id)
//     ) {
//       return (
//         <Banner status="warning" title={I18n.t("cod_fees.test_mode_title")}>
//           <p>{I18n.t("cod_fees.test_mode_msg")}</p>
//           <Button onClick={() => navigateTo("/subscription")}>
//             {I18n.t("cod_fees.upgrade_button")}
//           </Button>
//         </Banner>
//       );
//     }
//     if (setting.lockPaidFeature) {
//       return (
//         <Banner status="critical" title={I18n.t("cod_fees.locked_title")}>
//           <p>{I18n.t("cod_fees.locked_msg")}</p>
//           <Button onClick={() => setTab(7 + prepaidTabIncrement)}>
//             {I18n.t("cod_fees.upgrade_button")}
//           </Button>
//         </Banner>
//       );
//     }
//     return null;
//   };

//   const shippingSettingsUrl = `https://admin.shopify.com/store/${shop.shopify_domain.replace(
//     ".myshopify.com",
//     ""
//   )}/settings/shipping`;

//   const handleRedirect = (path) => {
//     if (window.app) {
//       const redirect = Redirect.create(window.app);
//       redirect.dispatch(Redirect.Action.APP, path);
//     } else {
//       window.location.href = path;
//     }
//   };

//   return (
//     <Page
//       fullWidth
//       backAction={{
//         content: "Back to Features",
//         onAction: () => handleRedirect("/features"),
//       }}
//       title={I18n.t("cod_fees.cod_fees_page_name")}
//     >
//       <Layout>
//         {renderBanner() && <Layout.Section>{renderBanner()}</Layout.Section>}

//         <Layout.AnnotatedSection
//           id="payment-method"
//           title={I18n.t("cod_fees.payment_method_heading")}
//           description={I18n.t("cod_fees.payment_method_info")}
//         >
//           <Card sectioned>
//             <Form onSubmit={handleSubmit}>
//               <Select
//                 label={I18n.t("cod_fees.select_cod_method")}
//                 options={
//                   paymentMethods?.paymentMethods?.map((m) => ({
//                     value: m.value,
//                     label: m.label,
//                   })) || []
//                 }
//                 onChange={handleSettingChange("paymentMethodName")}
//                 value={setting.paymentMethodName}
//               />
//             </Form>
//           </Card>
//         </Layout.AnnotatedSection>

//         <Layout.AnnotatedSection
//           id="shipping-rates"
//           title={I18n.t("cod_fees.shipping_rates_heading")}
//           description={I18n.t("cod_fees.shipping_rates_info")}
//         >
//           <Card sectioned>
//             {VideoThumbnailExample()}
//             <br />
//             <Layout>
//               <Layout.Section>
//                 <Text variant="headingSm">
//                   {I18n.t("cod_fees.simple_steps_title")}
//                 </Text>
//                 <List type="number">
//                   <List.Item>
//                     {I18n.t("cod_fees.step1")} &nbsp;
//                     <Link url={shippingSettingsUrl} external>
//                       {I18n.t("cod_fees.open_shipping_settings")}
//                     </Link>
//                   </List.Item>
//                   <List.Item>{I18n.t("cod_fees.step2")}</List.Item>
//                   <List.Item>{I18n.t("cod_fees.step3")}</List.Item>
//                   <List.Item>{I18n.t("cod_fees.step4")}</List.Item>
//                   <List.Item>{I18n.t("cod_fees.step5")}</List.Item>
//                   <List.Item>{I18n.t("cod_fees.step6")}</List.Item>
//                 </List>
//                 <Text>
//                   {I18n.t("cod_fees.need_help")}{" "}
//                   <Link onClick={() => window.$crisp.push(["do", "chat:open"])}>
//                     {I18n.t("cod_fees.chat_with_us")}
//                   </Link>
//                 </Text>
//               </Layout.Section>

//               <Layout.Section>
//                 {/* <div
//                   style={{
//                     position: "relative",
//                     paddingBottom: "33.25%",
//                     height: 0,
//                   }}
//                 >
//                   <iframe
//                     style={{
//                       position: "absolute",
//                       top: 0,
//                       left: 0,
//                       width: "100%",
//                       height: "100%",
//                     }}
//                     src="https://www.youtube.com/embed/I22U3fj6vKo"
//                     title="COD Fees Setup Tutorial"
//                     frameBorder="0"
//                     allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
//                     allowFullScreen
//                   />
//                 </div> */}

//                 {/* <Text fontWeight="bold">{I18n.t("cod_fees.video_title")}</Text>
//                 <Button
//                   size="slim"
//                   onClick={() =>
//                     window.open(
//                       "https://www.youtube.com/watch?v=I22U3fj6vKo",
//                       "_blank"
//                     )
//                   }
//                 >
//                   <span
//                     style={{
//                       display: "inline-flex",
//                       alignItems: "center",
//                       gap: "0.4rem",
//                     }}
//                   >
//                     <AiOutlineYoutube
//                       style={{ color: "#FF0000", fontSize: "20px" }}
//                       color="red"
//                     />
//                     {I18n.t("cod_fees.video_cta")}
//                   </span>
//                 </Button> */}
//               </Layout.Section>
//             </Layout>

//             <TextField
//               label={I18n.t("cod_fees.keyword_label")}
//               value={setting.codFeeShippingKeyword}
//               onChange={handleSettingChange("codFeeShippingKeyword")}
//               helpText={I18n.t("cod_fees.keyword_help")}
//             />
//             <br />

//             <Card background="bg-surface-warning" padding="600" rounded>
//               <Checkbox
//                 label={
//                   <Text fontWeight="bold" as="span">
//                     {I18n.t("cod_fees.enable_cod_fees")}
//                   </Text>
//                 }
//                 checked={setting.enableShippingCodFees}
//                 onChange={handleSettingChange("enableShippingCodFees")}
//               />
//               <Text tone="subdued">{I18n.t("cod_fees.cod_fees_note")}</Text>
//             </Card>
//           </Card>
//         </Layout.AnnotatedSection>
//       </Layout>
//     </Page>
//   );
// }
import React, {
  useContext,
  useRef,
  useEffect,
  useCallback,
  useState,
} from "react";
import {
  Page,
  Layout,
  Card,
  Form,
  Select,
  TextField,
  Checkbox,
  Banner,
  Text,
  List,
  Link,
  Button,
  Box,
  BlockStack,
  InlineGrid,
  Divider,
  SkeletonPage,
  SkeletonBodyText,
  SkeletonDisplayText,
  Badge,
} from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import useApi from "../Hooks/useApi";
import Api from "../Services/Api";
import I18n from "../i18n-lang";
import { navigateTo } from "../../utils/navigate";
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import { debugLog } from "../Modal/utilities/otpUtils";
import { SectionCard } from "./SettingsPrimitives";
import FeatureCallout from "./FeatureCallout";

const COD_FEES_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-17_at_2.13.13_PM_1.jpg?v=1791392886";
import { FreePlanFormNote } from "../Pages/CodForm/components/LimitCodNotes";
// Removed: import { Redirect } from "@shopify/app-bridge/actions"; // App Bridge v4 - use window.history.pushState instead

export default function CODFeesSettingsLayout() {
  const shopify = useAppBridge(); // Initialize v4 App Bridge
  const {
    loading: [loading, setLoading],
    plan: [plan],
    shop: [shop],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    tab: [tab, setTab],
    isPrepaidEnabled,
    contextualBar: [, setStoreContextualBar],
  } = useContext(StoreContext);

  const [contextualBar, setContextualBar] = useState(false);
  const [isDirty, setIsDirty] = useState(false);
  const prepaidTabIncrement = isPrepaidEnabled ? 1 : 0;
  const settingRef = useRef(setting);

  const [{ data: paymentMethods }, getPaymentMethods] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/payment_methods`,
      method: "GET",
    },
    { manual: true },
  );

  useEffect(() => {
    if (!paymentMethods) getPaymentMethods();
  }, [paymentMethods, getPaymentMethods]);

  useEffect(() => {
    settingRef.current = setting;
  }, [setting]);

  const resetLocalStates = useCallback(() => {
    setIsDirty(false);
    setContextualBar(false);
    setStoreContextualBar(false);
  }, [setStoreContextualBar]);

  const handleSubmit = useCallback(() => {
    setLoading(true);
    Api.post("/settings", settingRef.current)
      .then((res) => {
        setSetting(res.data);
        setOriginalSetting(res.data);
        resetLocalStates();
        shopify.toast.show(I18n.t("admin.settings_saved"));
      })
      .catch((err) => {
        debugLog(err);
        setContextualBar(false);
        setStoreContextualBar(false);
        shopify.toast.show(I18n.t("admin.settings_error"), { isError: true });
      })
      .finally(() => setLoading(false));
  }, [setLoading, setSetting, setOriginalSetting, resetLocalStates, shopify]);

  const handleDiscard = useCallback(() => {
    setSetting(JSON.parse(JSON.stringify(originalSetting)));
    resetLocalStates();
  }, [originalSetting, setSetting, resetLocalStates]);

  const handleSettingChange = useCallback(
    (key) => (value) => {
      setSetting((prev) => ({ ...prev, [key]: value }));
      setIsDirty(true);
      setContextualBar(true);
      setStoreContextualBar(true);
    },
    [setSetting, setStoreContextualBar],
  );

  useEffect(() => {
    setIsDirty(contextualBar);
  }, [contextualBar]);

  // Check if the interface should be disabled
  const isDisabled = () => {
    return (
      (!setting.locked &&
        setting.enableShippingCodFees &&
        (plan.name === "Free" || !shop.charge_id)) ||
      setting.lockPaidFeature
    );
  };

  // Get the appropriate message for disabled state
  const getDisabledMessage = () => {
    if (
      !setting.locked &&
      setting.enableShippingCodFees &&
      (plan.name === "Free" || !shop.charge_id)
    ) {
      return {
        status: "warning",
        title: I18n.t("cod_fees.test_mode_title"),
        message: I18n.t("cod_fees.test_mode_msg"),
        buttonText: I18n.t("cod_fees.upgrade_button"),
        buttonAction: () => navigateTo("/subscription"),
      };
    }
    if (setting.lockPaidFeature) {
      return {
        status: "warning",
        title: I18n.t("cod_fees.locked_title"),
        message: I18n.t("cod_fees.locked_msg"),
        buttonText: I18n.t("cod_fees.upgrade_button"),
        buttonAction: () => setTab(7 + prepaidTabIncrement),
      };
    }
    return null;
  };

  const shippingSettingsUrl = `https://admin.shopify.com/store/${shop.shopify_domain.replace(
    ".myshopify.com",
    "",
  )}/settings/shipping`;

  // Loading skeleton – matches COD Fees New: Layout.AnnotatedSection + Card/Form (payment method, etc.)
  if (!setting || !plan) {
    return (
      <SkeletonPage primaryAction>
        <Layout>
          <Layout.AnnotatedSection
            id="skeleton-payment-method"
            title=""
            description=""
          >
            <Card sectioned>
              <BlockStack gap="300">
                <SkeletonDisplayText size="small" />
                <SkeletonBodyText lines={1} />
                <SkeletonBodyText lines={1} />
                <Divider />
                <SkeletonDisplayText size="small" />
                <SkeletonBodyText lines={2} />
              </BlockStack>
            </Card>
          </Layout.AnnotatedSection>
          <Layout.AnnotatedSection id="skeleton-fee" title="" description="">
            <Card sectioned>
              <BlockStack gap="200">
                <SkeletonBodyText lines={1} />
                <SkeletonBodyText lines={1} />
              </BlockStack>
            </Card>
          </Layout.AnnotatedSection>
        </Layout>
      </SkeletonPage>
    );
  }

  const disabled = isDisabled();
  const disabledMessage = getDisabledMessage();

  return (
    <Page
      fullWidth={true}
      title={I18n.t("cod_fees.cod_fees_page_name")}
      subtitle={I18n.t("quick_onboarding_cod_fees.page_subtitle")}
    >
      {/* App Bridge v4 SaveBar */}
      <SaveBar data-save-bar open={isDirty}>
        <button
          variant="primary"
          onClick={handleSubmit}
          loading={loading ? "" : undefined}
          disabled={loading}
        >
          {I18n.t("admin.save")}
        </button>
        <button onClick={handleDiscard}>{I18n.t("admin.discard")}</button>
      </SaveBar>

      <Layout>
        <Layout.Section>
          <FeatureCallout
            illustration="payments"
            image={COD_FEES_CALLOUT_IMAGE}
            title={I18n.t("cod_fees.cod_fees_page_name")}
            description={I18n.t("quick_onboarding_cod_fees.page_subtitle")}
            docsUrl="https://codking.notion.site/Step-by-Step-Guide-for-setting-up-COD-fees-for-your-Shopify-store-12e6e71a63f980faa519e4dc35f617b7"
            videoUrl="https://youtu.be/I22U3fj6vKo?si=sJ5ZfDo4Am_jCX5y"
            showChat
            /* This screen's switch is enableShippingCodFees. codFeeEnabled is
               what decides which of the two COD fee screens renders at all,
               and is false whenever this one is on screen. */
            badge={
              setting?.enableShippingCodFees ? (
                <Badge tone="success" progress="complete">
                    {I18n.t("pre_order.enabled")}
                  </Badge>
                ) : (
                  <Badge tone="attention" progress="incomplete">
                    {I18n.t("pre_order.inactive")}
                  </Badge>
                )
              }
            />
        </Layout.Section>

        {/* COD Form: on the Free plan the fee applies to form orders */}
        <FreePlanFormNote
          feature="cod_fees"
          isFreePlan={plan.name === "Free" || !shop.charge_id}
          asLayoutSection
        />

        {disabledMessage && (
          <Layout.Section>
            <Banner
              status={disabledMessage.status}
              title={disabledMessage.title}
            >
              <p>{disabledMessage.message}</p>
              <Button onClick={disabledMessage.buttonAction}>
                {disabledMessage.buttonText}
              </Button>
            </Banner>
          </Layout.Section>
        )}
        <Layout.Section>
          <SectionCard
            title={I18n.t("cod_fees.payment_method_heading")}
            description={I18n.t("cod_fees.payment_method_info")}
          >
            <Form onSubmit={handleSubmit}>
              <Select
                label={I18n.t("cod_fees.select_cod_method")}
                options={
                  paymentMethods?.paymentMethods?.map((m) => ({
                    value: m.value,
                    label: m.label,
                  })) || []
                }
                onChange={
                  disabled ? () => {} : handleSettingChange("paymentMethodName")
                }
                value={setting.paymentMethodName}
                disabled={disabled}
              />
            </Form>
          </SectionCard>
        </Layout.Section>

        <Layout.Section>
          <SectionCard
            title={I18n.t("cod_fees.shipping_rates_heading")}
            description={I18n.t("cod_fees.shipping_rates_info")}
          >
            <Layout>
              <Layout.Section>
                <div
                  style={{
                    opacity: disabled ? 0.5 : 1,
                    pointerEvents: disabled ? "none" : "auto",
                  }}
                >
                  <Text variant="headingSm">
                    {I18n.t("cod_fees.simple_steps_title")}
                  </Text>
                  <List type="number">
                    <List.Item>
                      {I18n.t("cod_fees.step1")} &nbsp;
                      <Link url={shippingSettingsUrl} external>
                        {I18n.t("cod_fees.open_shipping_settings")}
                      </Link>
                    </List.Item>
                    <List.Item>{I18n.t("cod_fees.step2")}</List.Item>
                    <List.Item>{I18n.t("cod_fees.step3")}</List.Item>
                    <List.Item>{I18n.t("cod_fees.step4")}</List.Item>
                    <List.Item>{I18n.t("cod_fees.step5")}</List.Item>
                    <List.Item>{I18n.t("cod_fees.step6")}</List.Item>
                  </List>
                  <Text>
                    {I18n.t("cod_fees.need_help")}{" "}
                    <Link
                      onClick={() => window.$crisp.push(["do", "chat:open"])}
                    >
                      {I18n.t("cod_fees.chat_with_us")}
                    </Link>
                  </Text>
                </div>
              </Layout.Section>

              <Layout.Section>
                {/* <div
                  style={{
                    position: "relative",
                    paddingBottom: "33.25%",
                    height: 0,
                  }}
                >
                  <iframe
                    style={{
                      position: "absolute",
                      top: 0,
                      left: 0,
                      width: "100%",
                      height: "100%",
                    }}
                    src="https://www.youtube.com/embed/I22U3fj6vKo"
                    title="COD Fees Setup Tutorial"
                    frameBorder="0"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                    allowFullScreen
                  />
                </div> */}

                {/* <Text fontWeight="bold">{I18n.t("cod_fees.video_title")}</Text>
                <Button
                  size="slim"
                  onClick={() =>
                    window.open(
                      "https://www.youtube.com/watch?v=I22U3fj6vKo",
                      "_blank"
                    )
                  }
                >
                  <span
                    style={{
                      display: "inline-flex",
                      alignItems: "center",
                      gap: "0.4rem",
                    }}
                  >
                    <AiOutlineYoutube
                      style={{ color: "#FF0000", fontSize: "20px" }}
                      color="red"
                    />
                    {I18n.t("cod_fees.video_cta")}
                  </span>
                </Button> */}
              </Layout.Section>
            </Layout>

            <TextField
              label={I18n.t("cod_fees.keyword_label")}
              value={setting.codFeeShippingKeyword}
              onChange={
                disabled
                  ? () => {}
                  : handleSettingChange("codFeeShippingKeyword")
              }
              helpText={I18n.t("cod_fees.keyword_help")}
              disabled={disabled}
            />
            <br />

            <Card background="bg-surface-warning" padding="600" rounded>
              <div style={{ opacity: disabled ? 0.5 : 1 }}>
                <Checkbox
                  label={
                    <Text fontWeight="bold" as="span">
                      {I18n.t("cod_fees.enable_cod_fees")}
                    </Text>
                  }
                  checked={setting.enableShippingCodFees}
                  onChange={
                    disabled
                      ? () => {}
                      : handleSettingChange("enableShippingCodFees")
                  }
                  disabled={disabled}
                />
                <Text tone="subdued">{I18n.t("cod_fees.cod_fees_note")}</Text>
              </div>
            </Card>
          </SectionCard>
        </Layout.Section>
      </Layout>
    </Page>
  );
}

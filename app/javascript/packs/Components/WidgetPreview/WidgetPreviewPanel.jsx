import React, { useEffect, useMemo, useState } from "react";
import { BlockStack, Button, Card, InlineStack, Text } from "@shopify/polaris";
import I18n from "../../i18n-lang";
import LiveWidgetPreview from "./LiveWidgetPreview";

const isOn = (v) => v === true || v === "true" || v === 1 || v === "1";

// Only the screens a shopper would reach with the features turned on.
const buildScreens = (setting) => {
  const otpOn = isOn(setting?.enablePreOrderOtp);
  const partialOn = isOn(setting?.partialPaymentEnabled);
  const screens = [];
  if (otpOn) {
    screens.push({ key: "phone", label: I18n.t("checkout_form_preview.login") });
    screens.push({ key: "otp", label: I18n.t("checkout_form_preview.verify") });
    if (isOn(setting?.isPrefilledAddressEnabled)) {
      screens.push({ key: "address", label: I18n.t("checkout_form_preview.address") });
    }
  }
  if (partialOn) {
    screens.push({ key: "payment", label: I18n.t("checkout_form_preview.payments") });
  }
  if (screens.length) {
    screens.push({ key: "confirmed", label: I18n.t("checkout_form_preview.done") });
  }
  return screens;
};

/**
 * The live storefront widget with a row of screen tabs over it, limited to the
 * features that are on. LiveWidgetPreview sizes itself to its parent, so the
 * frame sits in a box of fixed height.
 */
const WidgetPreviewPanel = ({ setting, showTabs = true, height = 620 }) => {
  const screens = useMemo(() => buildScreens(setting), [setting]);
  const [screen, setScreen] = useState(screens[0]?.key);

  useEffect(() => {
    if (!screens.some((s) => s.key === screen)) setScreen(screens[0]?.key);
  }, [screens, screen]);

  return (
    <Card>
      <BlockStack gap="300">
        {screens.length === 0 ? (
          <Text variant="bodySm" tone="subdued" as="p">
            {I18n.t("checkout_form_preview.nothing_enabled")}
          </Text>
        ) : (
          <>
            {showTabs && (
              <InlineStack gap="150" wrap>
                {screens.map((s) => (
                  <Button
                    key={s.key}
                    size="micro"
                    pressed={s.key === screen}
                    onClick={() => setScreen(s.key)}
                  >
                    {s.label}
                  </Button>
                ))}
              </InlineStack>
            )}
            <div style={{ height }}>
              <LiveWidgetPreview setting={setting} screen={screen} />
            </div>
          </>
        )}
      </BlockStack>
    </Card>
  );
};

export default WidgetPreviewPanel;

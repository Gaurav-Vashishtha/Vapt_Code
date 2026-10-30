import React, { useContext, useState } from "react";
import {
  Page,
  Layout,
  Card,
  BlockStack,
  Text,
  Checkbox,
  Button,
  Banner,
} from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import I18n from "../../i18n-lang";
import Api from "../../Services/Api";
import CheckoutFormPreview from "../../Components/CheckoutPreview/CheckoutFormPreview";
import { hubNavigate } from "../../Components/SectionHub";

const AddressPrefillSettings = () => {
  const {
    setting: [setting, setSetting],
  } = useContext(StoreContext);

  const [enabled, setEnabled] = useState(!!setting?.isPrefilledAddressEnabled);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState(false);

  const dirty = enabled !== !!setting?.isPrefilledAddressEnabled;

  const handleSave = async () => {
    setSaving(true);
    setError(false);
    setSaved(false);
    try {
      const response = await Api.post("/settings", {
        ...setting,
        isPrefilledAddressEnabled: enabled,
      });
      if (response?.data) setSetting(response.data);
      setSaved(true);
    } catch (e) {
      setError(true);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Page
      title={I18n.t("admin.address_prefill", { defaultValue: "Address Prefill" })}
      subtitle={
        I18n.t("admin.address_prefill_description", { defaultValue: "Prefill the customer's address on the COD King form to speed up checkout." })
      }
      compactTitle
      backAction={{
        content: I18n.t("nav.checkout", { defaultValue: "Form / COD King Checkout" }),
        onAction: (e) => hubNavigate(e, "/checkout"),
      }}
      primaryAction={{
        content: I18n.t("admin.save", { defaultValue: "Save" }),
        onAction: handleSave,
        loading: saving,
        disabled: !dirty || saving,
      }}
    >
      <Layout>
        <Layout.Section variant="twoThirds">
          <BlockStack gap="400">
            {saved && (
              <Banner tone="success" onDismiss={() => setSaved(false)}>
                {I18n.t("admin.saved", { defaultValue: "Saved." })}
              </Banner>
            )}
            {error && (
              <Banner tone="critical" onDismiss={() => setError(false)}>
                {I18n.t("admin.save_failed", { defaultValue: "Could not save. Please try again." })}
              </Banner>
            )}
            <Card>
              <BlockStack gap="300">
                <Text variant="headingMd" as="h2">
                  {I18n.t("admin.address_prefill", { defaultValue: "Address Prefill" })}
                </Text>
                <Checkbox
                  label={
                    I18n.t("admin.address_prefill_toggle", { defaultValue: "Prefill the customer's saved address on the COD form" })
                  }
                  checked={enabled}
                  onChange={setEnabled}
                />
                <Text variant="bodySm" tone="subdued" as="p">
                  {I18n.t("admin.address_prefill_help", { defaultValue: "When enabled, returning customers see their address prefilled, reducing typing and drop-off." })}
                </Text>
              </BlockStack>
            </Card>
          </BlockStack>
        </Layout.Section>
        <Layout.Section variant="oneThird">
          <CheckoutFormPreview setting={{ ...setting, isPrefilledAddressEnabled: enabled }} />
        </Layout.Section>
      </Layout>
    </Page>
  );
};

export default AddressPrefillSettings;

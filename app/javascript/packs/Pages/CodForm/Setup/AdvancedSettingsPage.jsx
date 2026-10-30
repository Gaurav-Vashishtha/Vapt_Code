import React, { useCallback, useEffect, useState } from "react";
import { Badge, BlockStack, Button, InlineStack, Text } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import { navigateTo } from "../../../../utils/navigate";
import { codFormApi } from "../api";
import useResource from "../useResource";
import { setIn } from "../utils";
import { PATHS } from "../constants";
import { t } from "../i18n";
import Screen, { SaveErrorBanner } from "../components/Screen";
import ScreenSaveBar from "../components/ScreenSaveBar";
import OrderTotalCard from "./OrderTotalCard";
import AdvancedCard from "./AdvancedCard";
import { prepare } from "./SetupPage";

/** Shipping rates entry: how many rates are on, and the way into the rates screen. */
const ShippingRatesCard = () => {
  const [rates, setRates] = useState(null);
  useEffect(() => {
    let alive = true;
    codFormApi.shippingRates
      .index()
      .then((response) => alive && setRates((response && response.items) || []))
      .catch(() => alive && setRates([]));
    return () => {
      alive = false;
    };
  }, []);
  const active = (rates || []).filter((rate) => rate.active !== false).length;
  return (
    <SectionCard
      title={t("shipping.title", "Shipping rates")}
      description={t("shipping.subtitle", "The delivery options and prices buyers see in the COD Form.")}
    >
      <InlineStack align="space-between" blockAlign="center" gap="300">
        {rates === null ? (
          <Text as="span" tone="subdued">
            {t("common.loading", "Loading…")}
          </Text>
        ) : rates.length === 0 ? (
          <Badge tone="attention">{t("shipping.none_yet", "No shipping rate yet")}</Badge>
        ) : (
          <Text as="span">
            {t("shipping.active_count", "%{active} of %{total} rates active", { active, total: rates.length })}
          </Text>
        )}
        <Button onClick={() => navigateTo(PATHS.shipping)}>
          {t("shipping.manage", "Manage shipping rates")}
        </Button>
      </InlineStack>
    </SectionCard>
  );
};

/**
 * /features/cod-form/advanced — "Advanced settings" in the side panel: shipping rates (the
 * rates screen itself stays at /features/cod-form/shipping and keeps this item selected),
 * order total limits (VIS-4) and form behaviour (COD only through the form, COD fee tax,
 * discount codes, pay online, abandoned forms, upsell window, embedded mode, consent,
 * branding). Same `general` object and endpoint as Setup.
 */
const AdvancedSettingsPage = () => {
  const { data, setData, isDirty, loading, saving, error, saveError, save, discard, reload, clearSaveError } = useResource({
    load: () => codFormApi.setup.show(),
    save: (current) => codFormApi.setup.update(current.general),
    prepare,
  });

  const change = useCallback(
    (path, value) => setData((current) => setIn(current, ["general", ...path], value)),
    [setData],
  );

  return (
    <Screen
      title={t("setup.advanced_settings_title", "Advanced settings")}
      subtitle={t("setup.advanced_settings_subtitle", "Optional COD Form settings. The defaults suit most stores.")}
      loading={loading || !data}
      error={error}
      onRetry={reload}
      skeletonCards={2}
    >
      {data && (
        <BlockStack gap="400">
          <ScreenSaveBar open={isDirty} saving={saving} onSave={save} onDiscard={discard} />
          <SaveErrorBanner error={saveError} onDismiss={clearSaveError} />
          <ShippingRatesCard />
          <OrderTotalCard general={data.general} onChange={change} />
          <AdvancedCard general={data.general} onChange={change} />
        </BlockStack>
      )}
    </Screen>
  );
};

export default AdvancedSettingsPage;

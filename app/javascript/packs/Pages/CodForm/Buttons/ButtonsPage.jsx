import React, { useCallback } from "react";
import styled from "styled-components";
import { BlockStack, Card, InlineGrid, Text } from "@shopify/polaris";
import { codFormApi } from "../api";
import useResource from "../useResource";
import { DEFAULT_BUTTON_CONFIG } from "../defaults";
import { mergeDefaults, setIn } from "../utils";
import { t } from "../i18n";
import Screen, { SaveErrorBanner } from "../components/Screen";
import ScreenSaveBar from "../components/ScreenSaveBar";
import ButtonStyleCard from "./ButtonStyleCard";
import PlacementCard from "./PlacementCard";
import StickyCard from "./StickyCard";
import CartButtonsCard from "./CartButtonsCard";
import ThemeButtonsCard from "./ThemeButtonsCard";
import QuantityWidgetCard from "./QuantityWidgetCard";
import ButtonPreview from "./ButtonPreview";

const StickyColumn = styled.div`
  @media (min-width: 1040px) {
    position: sticky;
    top: 16px;
  }
`;

/* One layout only: the COD button next to the theme's own buttons, each of which can be
   hidden or renamed. It is stored as preset "C", the one that applies the Buy now rename.
   Express wallet buttons are left to the theme. */
const PRESET = "C";

const prepare = (raw) => {
  const config = mergeDefaults(DEFAULT_BUTTON_CONFIG, (raw && raw.config) || {});
  return { preset: PRESET, config: setIn(config, ["theme", "hide", "wallets"], false) };
};

/** /features/cod-form/buttons — COD button, the buttons of each page, live preview. */
const ButtonsPage = () => {
  const { data, setData, isDirty, loading, saving, error, saveError, save, discard, reload, clearSaveError } = useResource({
    load: () => codFormApi.button.show(),
    save: (current) => codFormApi.button.update({ preset: PRESET, config: current.config }),
    prepare,
  });

  const change = useCallback(
    (path, value) => setData((current) => setIn(current, ["config", ...path], value)),
    [setData],
  );

  return (
    <Screen
      title={t("buttons.title", "Buttons")}
      subtitle={t("buttons.page_subtitle", "The Buy with COD button and how it sits next to your theme's buttons.")}
      loading={loading || !data}
      error={error}
      onRetry={reload}
    >
      {data && (
        <>
          <ScreenSaveBar open={isDirty} saving={saving} onSave={save} onDiscard={discard} />
          <SaveErrorBanner error={saveError} onDismiss={clearSaveError} />
          <InlineGrid columns={{ xs: 1, lg: "3fr 2fr" }} gap="400" alignItems="start">
            <BlockStack gap="400">
              <ButtonStyleCard button={data.config.button} onChange={change} />
              <ThemeButtonsCard button={data.config.button} theme={data.config.theme} onChange={change} />
              <PlacementCard button={data.config.button} onChange={change} />
              <StickyCard button={data.config.button} onChange={change} />
              <QuantityWidgetCard widget={data.config.quantity_widget} onChange={change} />
              <CartButtonsCard button={data.config.button} onChange={change} />
            </BlockStack>
            <StickyColumn>
              <Card>
                <BlockStack gap="400">
                  <Text as="h2" variant="headingMd">
                    {t("common.preview", "Preview")}
                  </Text>
                  <ButtonPreview config={data.config} />
                </BlockStack>
              </Card>
            </StickyColumn>
          </InlineGrid>
        </>
      )}
    </Screen>
  );
};

export default ButtonsPage;

import React, { useCallback, useEffect, useRef, useState } from "react";
import { Badge, Banner, BlockStack, Box, Button, InlineStack, Spinner, Text } from "@shopify/polaris";
import { codFormApi } from "../api";
import { t } from "../i18n";
import EmbedTutorial from "./EmbedTutorial";

const POLL_MS = 4000;
const POLL_MAX = 30; // about two minutes after the theme editor is opened

/**
 * Quick onboarding, theme step: turn on the "COD Form" app embed. Shows whether the embed is
 * on in the live theme, opens the theme editor on it, and re-checks until it is found.
 * `onStatus(on, legacyOn)` tells the wizard whether the COD Form embed is on, and whether the
 * older "COD King OTP Block" embed is on (null when the theme could not be read).
 */
const OnboardingEmbedStep = ({ onStatus }) => {
  const [embed, setEmbed] = useState(null);
  const [checking, setChecking] = useState(false);
  const [waiting, setWaiting] = useState(false);
  const timer = useRef(null);
  const alive = useRef(true);
  const report = useRef(onStatus);
  report.current = onStatus;

  const apply = useCallback((value) => {
    if (!alive.current) return false;
    setEmbed(value || {});
    const on = !!(value && value.enabled === true);
    // Second argument: the older "COD King OTP Block" embed (true / false, null = unknown).
    const legacy = value && (value.legacy_enabled === true || value.legacy_enabled === false) ? value.legacy_enabled : null;
    if (report.current) report.current(on, legacy);
    return on;
  }, []);

  const stop = useCallback(() => {
    if (timer.current) clearInterval(timer.current);
    timer.current = null;
    if (alive.current) setWaiting(false);
  }, []);

  const check = useCallback(
    () =>
      codFormApi.setup
        .refreshEmbed()
        .then((data) => apply(data && data.embed))
        .catch(() => false),
    [apply],
  );

  useEffect(() => {
    alive.current = true;
    // Read the theme now, not the cached status: a merchant who just switched the embed off
    // (or on) must see the real state. The cached status is the fallback.
    codFormApi.setup
      .refreshEmbed()
      .catch(() => codFormApi.setup.show())
      .then((data) => apply(data && data.embed))
      .catch(() => apply(null));
    return () => {
      alive.current = false;
      if (timer.current) clearInterval(timer.current);
    };
  }, [apply]);

  // Coming back from the theme editor tab: read the theme again (both embeds).
  useEffect(() => {
    const onFocus = () => check();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [check]);

  const checkNow = () => {
    setChecking(true);
    check().then(() => alive.current && setChecking(false));
  };

  const openEditor = () => {
    if (embed && embed.theme_editor_url) window.open(embed.theme_editor_url, "_blank");
    stop();
    setWaiting(true);
    let count = 0;
    timer.current = setInterval(() => {
      count += 1;
      check().then((on) => {
        if (on || count >= POLL_MAX) stop();
      });
    }, POLL_MS);
  };

  const info = embed || {};
  const isOn = info.enabled === true;

  if (isOn) {
    return (
      <Box padding="400" background="bg-surface-success" borderRadius="300">
        <InlineStack gap="200" blockAlign="center">
          <Badge tone="success">{t("setup.embed_on", "On in your theme")}</Badge>
          <Text variant="bodyMd" as="p">
            {t("onboarding.embed_on_body", "The COD Form app embed is on. The Buy with COD button will show on your store.")}
          </Text>
        </InlineStack>
      </Box>
    );
  }

  return (
    <Box padding="500" borderWidth="025" borderColor="border" borderRadius="300">
      <BlockStack gap="400">
        <BlockStack gap="200">
          <InlineStack gap="200" blockAlign="center">
            <Text variant="headingMd" as="h3">
              {t("onboarding.embed_title", "COD Form app embed")}
            </Text>
            <Badge tone="attention">{t("onboarding.embed_required", "Required")}</Badge>
            {embed === null && <Spinner size="small" />}
          </InlineStack>
          <Text variant="bodyMd" as="p" tone="subdued">
            {t(
              "onboarding.embed_body2",
              "The Buy with COD button only shows after this one step in your theme. It takes about 20 seconds.",
            )}
          </Text>
        </BlockStack>
        <EmbedTutorial />
        <InlineStack gap="300">
          <Button variant="primary" size="large" onClick={openEditor} disabled={!info.theme_editor_url}>
            {t("setup.embed_open_editor", "Open theme editor")}
          </Button>
          <Button variant="tertiary" onClick={checkNow} loading={checking}>
            {t("setup.embed_refresh", "Check again")}
          </Button>
        </InlineStack>
        {waiting && (
          <Banner tone="info">
            <InlineStack gap="200" blockAlign="center">
              <Spinner size="small" />
              <Text variant="bodyMd" as="span">
                {t("onboarding.embed_waiting2", "Waiting for you to click Save in the theme editor… This updates by itself.")}
              </Text>
            </InlineStack>
          </Banner>
        )}
      </BlockStack>
    </Box>
  );
};

export default OnboardingEmbedStep;

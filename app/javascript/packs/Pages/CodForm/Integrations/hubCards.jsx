import React, { useEffect, useState } from "react";
import styled from "styled-components";
import { codFormApi } from "../api";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { PATHS } from "../constants";
import { tg } from "../i18n";

const Mark = styled.span`
  flex: 0 0 auto;
  width: 40px;
  height: 40px;
  border-radius: 10px;
  border: 1px solid var(--p-color-border-secondary, #e3e3e3);
  background: ${(p) => p.$bg || "#ffffff"};
  color: ${(p) => p.$fg || "#1a1a1a"};
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 13px;
  letter-spacing: 0.02em;
`;

const mark = (text, bg, fg) => (
  <Mark $bg={bg} $fg={fg} aria-hidden="true">
    {text}
  </Mark>
);

/**
 * Cards the COD Form module adds to the Integrations directory: TikTok,
 * form pixels, Google Sheets, Klaviyo, Omnisend, address autocomplete.
 * Returns [] until the module is known to be on for the shop, so the
 * directory is unchanged for everyone else. Items have the shape the
 * directory already renders: {key, title, category, description, connected, href, mark}.
 */
const useCodFormIntegrationCards = () => {
  const bootstrap = useCodFormBootstrap();
  const enabled = !!bootstrap && bootstrap.moduleEnabled;
  const [state, setState] = useState({ pixels: [], integrations: [] });

  useEffect(() => {
    if (!enabled) return undefined;
    let cancelled = false;
    Promise.all([
      codFormApi.pixels.index().catch(() => ({ items: [] })),
      codFormApi.integrations.index().catch(() => ({ items: [] })),
    ]).then(([pixels, integrations]) => {
      if (!cancelled) setState({ pixels: (pixels && pixels.items) || [], integrations: (integrations && integrations.items) || [] });
    });
    return () => {
      cancelled = true;
    };
  }, [enabled]);

  if (!enabled) return [];

  const tracking = tg("integrations.category_tracking", "Conversion tracking");
  const formCategory = tg("integrations.category_cod_form", "COD Form");
  const hasPixel = (platform) => state.pixels.some((pixel) => pixel.platform === platform && pixel.enabled !== false);
  const isConnected = (provider) => state.integrations.some((item) => item.provider === provider && item.status === "connected");

  return [
    {
      key: "codkf-tiktok",
      title: tg("integrations.tiktok.title", "TikTok Pixel"),
      category: tracking,
      description: tg("integrations.tiktok.card_description", "Send COD Form opens and orders to TikTok, from the browser and the Events API."),
      connected: hasPixel("tiktok"),
      href: PATHS.tiktok,
      mark: mark("TT", "#111111", "#ffffff"),
    },
    {
      key: "codkf-form-pixels",
      title: tg("integrations.form_pixels.title", "COD Form pixels"),
      category: tracking,
      description: tg("integrations.form_pixels.card_description", "More Meta pixels, GA4, Google Ads, Snapchat and Pinterest for orders placed in the COD Form."),
      connected: state.pixels.some((pixel) => pixel.platform !== "tiktok" && pixel.enabled !== false),
      href: PATHS.formPixels,
      mark: mark("PX", "#eef4ff", "#1f4fbf"),
    },
    {
      key: "codkf-google-sheets",
      title: tg("integrations.google_sheets.title", "Google Sheets"),
      category: formCategory,
      description: tg("integrations.google_sheets.card_description", "Add each COD Form order to a Google Sheet as it is placed."),
      connected: isConnected("google_sheets"),
      href: PATHS.googleSheets,
      mark: mark("GS", "#e8f5e9", "#1b7f3b"),
    },
    {
      key: "codkf-klaviyo",
      title: tg("integrations.klaviyo.title", "Klaviyo"),
      category: formCategory,
      description: tg("integrations.klaviyo.card_description", "Send form order and abandoned form events to Klaviyo."),
      connected: isConnected("klaviyo"),
      href: `${PATHS.formPixels}#klaviyo`,
      mark: mark("KL", "#111111", "#ffffff"),
    },
    {
      key: "codkf-omnisend",
      title: tg("integrations.omnisend.title", "Omnisend"),
      category: formCategory,
      description: tg("integrations.omnisend.card_description", "Send form order and abandoned form events to Omnisend."),
      connected: isConnected("omnisend"),
      href: `${PATHS.formPixels}#omnisend`,
      mark: mark("OM", "#f3f0ff", "#4b2fbf"),
    },
    {
      key: "codkf-autocomplete",
      title: tg("integrations.address_autocomplete.title", "Google address autocomplete"),
      category: formCategory,
      description: tg("integrations.address_autocomplete.card_description", "Suggest addresses in the COD Form with your own Google Maps key."),
      connected: false,
      href: `${PATHS.setup}#address-autocomplete`,
      mark: mark("AD", "#fff4e5", "#8a5300"),
    },
  ];
};

export default useCodFormIntegrationCards;

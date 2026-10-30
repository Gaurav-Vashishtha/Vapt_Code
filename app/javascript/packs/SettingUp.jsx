import React, { useEffect, useState } from "react";
import { Box, BlockStack, Spinner, Text, Button } from "@shopify/polaris";
import Api from "./Services/Api";

// Shown on first install while the offline Admin token is minted. Calls
// POST /session/bootstrap (which exchanges the session token for an offline
// token), then reloads into the full app. Retries a few times on a slow/failed
// Shopify response before surfacing a manual reload.
const MAX_ATTEMPTS = 3;
const RETRY_DELAY_MS = 2000;
// Each bootstrap call gets its own deadline, and the whole screen gets a hard
// ceiling, so a hung token fetch or a reload that never happens (seen in
// mobile WebViews) ends on the manual Reload prompt instead of an endless spinner.
const REQUEST_TIMEOUT_MS = 15000;
const WATCHDOG_MS = 30000;

const SettingUp = () => {
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    let attempt = 0;
    let timer = null;
    const watchdog = setTimeout(() => {
      if (!cancelled) setFailed(true);
    }, WATCHDOG_MS);

    const run = async () => {
      attempt += 1;
      try {
        const res = await Api.post("/session/bootstrap", {}, { timeout: REQUEST_TIMEOUT_MS });
        if (cancelled) return;
        if (res?.data?.ok) {
          // Watchdog stays armed: if the reload never happens, it still
          // flips this screen to the manual prompt.
          window.location.reload();
          return;
        }
        throw new Error("bootstrap not ok");
      } catch (e) {
        if (cancelled) return;
        if (attempt < MAX_ATTEMPTS) {
          timer = setTimeout(run, RETRY_DELAY_MS);
        } else {
          clearTimeout(watchdog);
          setFailed(true);
        }
      }
    };

    run();
    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
      clearTimeout(watchdog);
    };
  }, []);

  return (
    <Box padding="800">
      <BlockStack gap="400" align="center" inlineAlign="center">
        {failed ? (
          <>
            <Text as="p" variant="headingMd">
              We're having trouble reaching Shopify
            </Text>
            <Text as="p" tone="subdued" alignment="center">
              Your store is installed — please reload to finish setting up.
              If you're on the Shopify mobile app and this keeps happening,
              open COD King from Shopify admin on a computer.
            </Text>
            <Button variant="primary" onClick={() => window.location.reload()}>
              Reload
            </Button>
          </>
        ) : (
          <>
            <Spinner accessibilityLabel="Setting up your store" size="large" />
            <Text as="p" variant="headingMd">
              Setting up your store…
            </Text>
            <Text as="p" tone="subdued" alignment="center">
              This only takes a few seconds.
            </Text>
          </>
        )}
      </BlockStack>
    </Box>
  );
};

export default SettingUp;

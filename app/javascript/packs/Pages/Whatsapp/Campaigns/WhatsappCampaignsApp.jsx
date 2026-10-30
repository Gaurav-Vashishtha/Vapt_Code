import React, { useState, useEffect, useCallback, useRef } from "react";
import { BlockStack, Banner, Tabs, Card, SkeletonBodyText, Badge, Button } from "@shopify/polaris";
import FeatureCallout from "../../../Components/FeatureCallout";
import WhatsappLayout from "../WhatsappLayout";
import { navigateTo } from "../../../../utils/navigate";
import { api } from "./api";
import { t, paths, BASE_PATH } from "./copy";
import SetupChecklist, { setupSteps, isReadyToSend } from "./SetupChecklist";
import CampaignsTab, { CampaignStats } from "./CampaignsTab";
import AudiencesTab from "./AudiencesTab";
import CampaignBuilder from "./CampaignBuilder";
import CampaignReport from "./CampaignReport";
import RecipePicker from "./RecipePicker";

const TABS = ["campaigns", "audiences"];

const tabFromUrl = (path) => {
  if (path === "/features/whatsapp/audience") return 1;
  const tab = new URLSearchParams(window.location.search).get("tab");
  return Math.max(0, TABS.indexOf(tab));
};

const CampaignsHome = ({ path }) => {
  const [tab, setTab] = useState(() => tabFromUrl(path));
  const [overview, setOverview] = useState(null);
  const [error, setError] = useState("");
  const [syncing, setSyncing] = useState(false);
  const autoSynced = useRef(false);
  const importRef = useRef(null);

  const loadOverview = useCallback(async () => {
    try {
      setOverview(await api("/api/whatsapp/campaigns/overview"));
    } catch (e) { setError(e.message); }
  }, []);

  useEffect(() => { loadOverview(); }, [loadOverview]);

  // Old links (Sidekick, bookmarks) move onto this page's own address, which is
  // also what makes the sidebar highlight "WhatsApp campaigns".
  useEffect(() => {
    if (path.startsWith("/features/whatsapp/")) {
      window.history.replaceState({}, "", paths.home(tab === 1 ? "audiences" : undefined));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [path]);

  const sync = useCallback(async () => {
    setSyncing(true);
    try {
      await api("/api/whatsapp/contacts/sync", { method: "POST" });
      await loadOverview();
    } catch (e) { setError(e.message); } finally { setSyncing(false); }
  }, [loadOverview]);

  // Contacts come from the store without anyone pressing a button: the first
  // visit after connecting (and once a day after, when the last sync status has
  // expired) starts a sync in the background.
  const syncStatus = overview?.contacts?.sync?.status;
  useEffect(() => {
    if (!overview || autoSynced.current || !overview.account?.connected) return;
    if (!overview.contacts?.sync) {
      autoSynced.current = true;
      sync();
    }
  }, [overview, sync]);

  useEffect(() => {
    if (!["queued", "running"].includes(syncStatus)) return undefined;
    const timer = setInterval(loadOverview, 4000);
    return () => clearInterval(timer);
  }, [syncStatus, loadOverview]);

  const selectTab = (index) => {
    setTab(index);
    // Remember the tab in the address so a refresh or the back button keeps it.
    const params = new URLSearchParams(window.location.search);
    if (index === 0) params.delete("tab");
    else params.set("tab", TABS[index]);
    const qs = params.toString();
    window.history.replaceState({}, "", `${BASE_PATH}${qs ? `?${qs}` : ""}`);
  };

  const openUpload = () => {
    selectTab(1);
    // The Contacts card registers its opener once the tab has rendered.
    setTimeout(() => importRef.current?.(), 0);
  };

  const ready = isReadyToSend(overview);
  const steps = overview ? setupSteps(overview, { onSync: sync, syncing, onUpload: openUpload }) : [];
  const setupDone = steps.length > 0 && steps.every((s) => s.done);

  return (
    <WhatsappLayout
      title={t("page_title", "WhatsApp campaigns")}
      subtitle={t("page_subtitle", "Send offers and announcements to your customers on WhatsApp.")}
      hideBack
      primaryAction={{
        content: t("create_campaign", "Create campaign"),
        onAction: () => navigateTo(paths.newCampaign()),
        disabled: !ready,
        helpText: ready ? undefined : t("create_disabled", "Finish the setup steps first"),
      }}
    >
      <BlockStack gap="400">
        {error && <Banner tone="critical" onDismiss={() => setError("")}>{error}</Banner>}

        {!overview ? (
          <Card><SkeletonBodyText lines={6} /></Card>
        ) : (
          <>
            <FeatureCallout
              title={t("callout_title", "Reach customers where they reply")}
              description={t(
                "callout_desc",
                "Pick an audience, choose an approved template, and send now or schedule it. Every message is tracked from sent to read and reply.",
              )}
              illustration="campaigns"
              badge={
                ready
                  ? <Badge tone="success">{t("callout_ready", "Ready to send")}</Badge>
                  : <Badge tone="attention">{t("callout_setup", "Setup needed")}</Badge>
              }
              actions={
                <Button onClick={() => selectTab(1)}>
                  {t("callout_audiences", "Open audiences")}
                </Button>
              }
            />
            {!setupDone && <SetupChecklist steps={steps} />}
            {overview.campaigns_count > 0 && <CampaignStats stats={overview.last_30_days} />}

            <Tabs
              tabs={[
                { id: "campaigns", content: t("tab_campaigns", "Campaigns"), panelID: "campaigns-panel" },
                { id: "audiences", content: t("tab_audiences", "Audiences"), panelID: "audiences-panel" },
              ]}
              selected={tab}
              onSelect={selectTab}
            />

            {tab === 0 && <RecipePicker disabled={!ready} onError={setError} />}
            {tab === 0 && (
              <CampaignsTab
                ready={ready}
                scheduleTz={overview.schedule_timezone}
                onChanged={loadOverview}
                onError={setError}
              />
            )}
            {tab === 1 && (
              <AudiencesTab
                overview={overview}
                onSync={sync}
                syncing={syncing}
                onChanged={loadOverview}
                onError={setError}
                importRef={importRef}
              />
            )}
          </>
        )}
      </BlockStack>
    </WhatsappLayout>
  );
};

// One entry for every campaigns URL:
//   /features/whatsapp-campaigns            list (?tab=audiences for audiences)
//   /features/whatsapp-campaigns/new        builder
//   /features/whatsapp-campaigns/:id/edit   builder for a draft
//   /features/whatsapp-campaigns/:id        results
// The old /features/whatsapp/campaigns and /audience URLs land on the list.
const WhatsappCampaignsApp = ({ path }) => {
  const rest = path.startsWith(`${BASE_PATH}/`) ? path.slice(BASE_PATH.length + 1).split("/") : [];

  // One key for both builder URLs: saving a new draft rewrites the address from
  // /new to /:id/edit, and the page must keep what the merchant has entered.
  if (rest[0] === "new") return <CampaignBuilder key="builder" />;
  if (/^\d+$/.test(rest[0] || "")) {
    if (rest[1] === "edit") return <CampaignBuilder key="builder" id={rest[0]} />;
    return <CampaignReport key={`report-${rest[0]}`} id={rest[0]} />;
  }
  return <CampaignsHome path={path} />;
};

export const isCampaignsPath = (path) =>
  path === BASE_PATH ||
  path.startsWith(`${BASE_PATH}/`) ||
  path === "/features/whatsapp/campaigns" ||
  path === "/features/whatsapp/audience";

export default WhatsappCampaignsApp;

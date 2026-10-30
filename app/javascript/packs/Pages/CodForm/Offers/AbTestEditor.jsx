import React, { useEffect, useMemo, useState } from "react";
import { Badge, Banner, BlockStack, Button, DataTable, InlineGrid, InlineStack, List, Modal, Select, Text, TextField } from "@shopify/polaris";
import { DeleteMinor } from "@shopify/polaris-icons";
import { navigateTo } from "../../../../utils/navigate";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import { codFormApi, parseError } from "../api";
import useResource from "../useResource";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { newAbTest } from "../defaults";
import { FEATURES, LIMITS, PATHS } from "../constants";
import { formatMoney } from "../money";
import { formatDateTime, mergeDefaults, toInt } from "../utils";
import { t } from "../i18n";
import Gate from "../components/Gate";
import Screen, { SaveErrorBanner } from "../components/Screen";
import ScreenSaveBar from "../components/ScreenSaveBar";
import { OFFER_SEGMENTS, offerMeta } from "./offerMeta";
import { abStatusLabel } from "./AbTestsPage";

const KEYS = ["a", "b", "c", "d"];

/** A/B test editor (OFF-12): 2–4 variants with weights summing to 100; locked once started. */
const AbTestEditor = ({ id }) => {
  const bootstrap = useCodFormBootstrap();
  const isNew = !id || id === "new";
  const [offers, setOffers] = useState([]);
  const [busy, setBusy] = useState(null);
  const [actionError, setActionError] = useState(null);
  const [showProblems, setShowProblems] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [leaveTo, setLeaveTo] = useState(null);

  const resource = useResource({
    load: () => (isNew ? Promise.resolve(newAbTest("quantity")) : codFormApi.abTests.show(id)),
    save: (test) => {
      const body = { name: test.name, offer_type: test.offer_type, variants: test.variants };
      return isNew ? codFormApi.abTests.create(body) : codFormApi.abTests.update(id, body);
    },
    prepare: (raw) => mergeDefaults(newAbTest((raw && raw.offer_type) || "quantity"), raw || {}),
    deps: [id],
  });
  const { data, setData, isDirty, loading, saving, error, saveError, save, discard, reload, replace, clearSaveError } = resource;
  const offerType = data ? data.offer_type : null;

  useEffect(() => {
    if (!offerType) return;
    codFormApi.offers
      .index(offerType)
      .then((response) => setOffers(((response && response.items) || []).filter((offer) => offer.status !== "archived")))
      .catch(() => setOffers([]));
  }, [offerType]);

  useEffect(() => {
    if (!leaveTo) return undefined;
    const timer = setTimeout(() => navigateTo(leaveTo), 60);
    return () => clearTimeout(timer);
  }, [leaveTo]);

  const variants = (data && data.variants) || [];
  const locked = !!data && (data.status !== "draft" || !!data.started_at);
  const weightSum = variants.reduce((sum, variant) => sum + (Number(variant.weight) || 0), 0);

  const problems = useMemo(() => {
    if (!data) return [];
    const list = [];
    if (!data.name || data.name.trim() === "") list.push(t("offers.ab_error_name", "Give the test a name."));
    if (variants.length < LIMITS.AB_VARIANTS_MIN || variants.length > LIMITS.AB_VARIANTS_MAX) {
      list.push(t("offers.ab_error_count", "A test needs 2 to 4 variants."));
    }
    if (weightSum !== 100) list.push(t("offers.ab_error_weights", "The traffic shares must add up to 100%. They add up to %{sum}%.", { sum: weightSum }));
    const offerIds = variants.map((variant) => (variant.offer_id == null ? "control" : String(variant.offer_id)));
    if (new Set(offerIds).size !== offerIds.length) list.push(t("offers.ab_error_duplicate", "Each variant needs a different offer."));
    if (variants.every((variant) => variant.offer_id == null)) list.push(t("offers.ab_error_no_offer", "Pick an offer for at least one variant."));
    return list;
  }, [data, variants, weightSum]);

  const patchVariant = (index, patch) =>
    setData((current) => ({
      ...current,
      variants: current.variants.map((variant, i) => (i === index ? { ...variant, ...patch } : variant)),
    }));

  const addVariant = () =>
    setData((current) => {
      const used = current.variants.map((variant) => variant.key);
      const key = KEYS.find((candidate) => !used.includes(candidate)) || `v${current.variants.length + 1}`;
      return { ...current, variants: [...current.variants, { key, offer_id: null, weight: 0 }] };
    });

  const splitEvenly = () =>
    setData((current) => {
      const count = current.variants.length;
      const base = Math.floor(100 / count);
      return {
        ...current,
        variants: current.variants.map((variant, index) => ({ ...variant, weight: index === 0 ? 100 - base * (count - 1) : base })),
      };
    });

  const handleSave = async () => {
    if (problems.length > 0) {
      setShowProblems(true);
      return false;
    }
    setShowProblems(false);
    const ok = await save();
    if (ok && isNew) setLeaveTo(PATHS.abTests);
    return ok;
  };

  const act = (key, action) => {
    setBusy(key);
    setActionError(null);
    return action()
      .then((test) => {
        if (test && test.id) replace(test);
        else return reload();
        return undefined;
      })
      .catch((err) => setActionError(parseError(err)))
      .then(() => setBusy(null));
  };

  const start = async () => {
    if (problems.length > 0) {
      setShowProblems(true);
      return;
    }
    if (isDirty) {
      const ok = await save();
      if (!ok) return;
    }
    act("start", () => codFormApi.abTests.start(id));
  };

  const remove = () => {
    setBusy("delete");
    codFormApi.abTests
      .destroy(id)
      .then(() => {
        setConfirmDelete(false);
        setLeaveTo(PATHS.abTests);
      })
      .catch((err) => {
        setActionError(parseError(err));
        setBusy(null);
      });
  };

  const results = (data && data.results) || [];
  const money = (cents) => formatMoney(cents, bootstrap && bootstrap.moneyFormat, bootstrap && bootstrap.currency);
  const offerName = (offerId) => {
    if (offerId == null) return t("offers.ab_control", "Show nothing (control)");
    const offer = offers.find((item) => String(item.id) === String(offerId));
    return offer ? offer.name : `#${offerId}`;
  };

  return (
    <Screen
      title={isNew ? t("offers.ab_new", "New A/B test") : (data && data.name) || t("offers.ab_tests_title", "A/B tests")}
      titleMetadata={data && !isNew ? <Badge tone={data.status === "running" ? "success" : undefined}>{abStatusLabel(data.status)}</Badge> : undefined}
      backPath={PATHS.abTests}
      backLabel={t("offers.ab_tests_title", "A/B tests")}
      secondaryActions={
        isNew || (data && data.status === "running")
          ? undefined
          : [{ content: t("common.delete", "Delete"), destructive: true, onAction: () => setConfirmDelete(true) }]
      }
      loading={loading || !data}
      error={error}
      onRetry={reload}
    >
      <Gate feature={FEATURES.AB_TESTS} title={t("offers.ab_tests_title", "A/B tests")}>
        {data && (
          <>
            {!locked && (
              <ScreenSaveBar
                open={(isDirty || isNew) && !leaveTo}
                saving={saving}
                onSave={handleSave}
                onDiscard={isNew ? () => setLeaveTo(PATHS.abTests) : discard}
              />
            )}
            <SaveErrorBanner error={saveError || actionError} onDismiss={() => { clearSaveError(); setActionError(null); }} />
            {showProblems && problems.length > 0 && (
              <Banner tone="critical" title={t("offers.problems_title", "Fix these before saving")} onDismiss={() => setShowProblems(false)}>
                <List type="bullet">
                  {problems.map((problem, index) => (
                    <List.Item key={index}>{problem}</List.Item>
                  ))}
                </List>
              </Banner>
            )}
            {locked && (
              <Banner tone="info">
                <p>{t("offers.ab_locked", "A started test cannot be changed, so its results stay comparable. Stop it and create a new test to try something else.")}</p>
              </Banner>
            )}

            <SectionCard title={t("offers.ab_setup_title", "Test")}>
              <BlockStack gap="400">
                <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                  <TextField
                    label={t("offers.name", "Name")}
                    value={data.name || ""}
                    onChange={(value) => setData((current) => ({ ...current, name: value }))}
                    disabled={locked}
                    maxLength={80}
                    autoComplete="off"
                  />
                  <Select
                    label={t("offers.ab_offer_type", "Kind of offer")}
                    options={OFFER_SEGMENTS.map((segment) => ({ value: offerMeta(segment).offerType, label: offerMeta(segment).title }))}
                    value={data.offer_type}
                    disabled={locked || !isNew}
                    onChange={(value) =>
                      setData((current) => ({
                        ...current,
                        offer_type: value,
                        variants: current.variants.map((variant) => ({ ...variant, offer_id: null })),
                      }))
                    }
                  />
                </InlineGrid>
                {data.started_at && (
                  <Text as="p" variant="bodySm" tone="subdued">
                    {t("offers.ab_started_at", "Started %{date}", { date: formatDateTime(data.started_at) })}
                    {data.stopped_at ? ` · ${t("offers.ab_stopped_at", "Stopped %{date}", { date: formatDateTime(data.stopped_at) })}` : ""}
                  </Text>
                )}
              </BlockStack>
            </SectionCard>

            <SectionCard
              title={t("offers.ab_variants_title", "Variants")}
              description={t("offers.ab_variants_help", "Each buyer sees one variant for the whole visit. Shares must add up to 100%.")}
            >
              <BlockStack gap="400">
                {variants.map((variant, index) => (
                  <InlineStack key={variant.key} gap="300" blockAlign="end" wrap>
                    <div style={{ flex: "2 1 220px" }}>
                      <Select
                        label={t("offers.ab_variant_label", "Variant %{key}", { key: String(variant.key).toUpperCase() })}
                        options={[
                          { value: "", label: t("offers.ab_control", "Show nothing (control)") },
                          ...offers.map((offer) => ({ value: String(offer.id), label: offer.name || `#${offer.id}` })),
                        ]}
                        value={variant.offer_id == null ? "" : String(variant.offer_id)}
                        disabled={locked}
                        onChange={(value) => patchVariant(index, { offer_id: value === "" ? null : toInt(value) })}
                      />
                    </div>
                    <div style={{ flex: "1 1 120px" }}>
                      <TextField
                        label={t("offers.ab_weight", "Traffic share")}
                        type="number"
                        min={0}
                        max={100}
                        suffix="%"
                        value={String(variant.weight == null ? 0 : variant.weight)}
                        disabled={locked}
                        onChange={(value) => patchVariant(index, { weight: Math.min(100, Math.max(0, toInt(value, 0))) })}
                        autoComplete="off"
                      />
                    </div>
                    {!locked && (
                      <Button
                        icon={DeleteMinor}
                        tone="critical"
                        accessibilityLabel={t("common.delete", "Delete")}
                        disabled={variants.length <= LIMITS.AB_VARIANTS_MIN}
                        onClick={() => setData((current) => ({ ...current, variants: current.variants.filter((_, i) => i !== index) }))}
                      />
                    )}
                  </InlineStack>
                ))}
                {!locked && (
                  <InlineStack gap="200" blockAlign="center" wrap>
                    <Button onClick={addVariant} disabled={variants.length >= LIMITS.AB_VARIANTS_MAX}>
                      {t("offers.ab_add_variant", "Add variant")}
                    </Button>
                    <Button variant="plain" onClick={splitEvenly}>
                      {t("offers.ab_split_evenly", "Split evenly")}
                    </Button>
                    <Text as="span" variant="bodySm" tone={weightSum === 100 ? "subdued" : "critical"}>
                      {t("offers.ab_weight_sum", "Total: %{sum}%", { sum: weightSum })}
                    </Text>
                  </InlineStack>
                )}
                {offers.length === 0 && !locked && (
                  <Banner tone="info">
                    <p>{t("offers.ab_no_offers", "There is no offer of this kind yet. Create the offers first, then come back.")}</p>
                  </Banner>
                )}
              </BlockStack>
            </SectionCard>

            {!isNew && (
              <SectionCard title={t("offers.ab_run_title", "Run the test")}>
                <InlineStack gap="200">
                  {data.status === "draft" && (
                    <Button variant="primary" onClick={start} loading={busy === "start"}>
                      {t("offers.ab_start", "Start test")}
                    </Button>
                  )}
                  {data.status === "running" && (
                    <Button tone="critical" onClick={() => act("stop", () => codFormApi.abTests.stop(id))} loading={busy === "stop"}>
                      {t("offers.ab_stop", "Stop test")}
                    </Button>
                  )}
                  {data.status === "stopped" && (
                    <Text as="span" tone="subdued">
                      {t("offers.ab_stopped_note", "This test has ended.")}
                    </Text>
                  )}
                </InlineStack>
              </SectionCard>
            )}

            {!isNew && data.status !== "draft" && (
              <SectionCard title={t("offers.ab_results_title", "Results")}>
                {results.length === 0 ? (
                  <Text as="p" tone="subdued">
                    {t("offers.ab_results_empty", "No results yet. They appear as buyers open the form.")}
                  </Text>
                ) : (
                  <DataTable
                    columnContentTypes={["text", "numeric", "numeric", "numeric", "numeric"]}
                    headings={[
                      t("offers.ab_col_variant", "Variant"),
                      t("offers.ab_col_views", "Views"),
                      t("offers.ab_col_accepts", "Accepted"),
                      t("offers.ab_col_orders", "Orders"),
                      t("offers.ab_col_revenue", "Revenue"),
                    ]}
                    rows={results.map((row) => {
                      const variant = variants.find((item) => item.key === row.key);
                      return [
                        `${String(row.key).toUpperCase()} · ${offerName(variant ? variant.offer_id : null)}${data.winner_key === row.key ? " ★" : ""}`,
                        row.views || 0,
                        row.accepts || 0,
                        row.orders || 0,
                        money(row.revenue_cents || 0),
                      ];
                    })}
                  />
                )}
              </SectionCard>
            )}
          </>
        )}
      </Gate>

      <Modal
        open={confirmDelete}
        onClose={() => setConfirmDelete(false)}
        title={t("offers.ab_delete_title", "Delete this test?")}
        primaryAction={{ content: t("common.delete", "Delete"), destructive: true, onAction: remove, loading: busy === "delete" }}
        secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: () => setConfirmDelete(false) }]}
      >
        <Modal.Section>
          <Text as="p">{t("offers.ab_delete_body", "The test and its results are removed. The offers themselves are kept.")}</Text>
        </Modal.Section>
      </Modal>
    </Screen>
  );
};

export default AbTestEditor;

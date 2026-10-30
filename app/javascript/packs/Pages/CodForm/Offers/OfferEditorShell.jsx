import React, { useCallback, useEffect, useMemo, useState } from "react";
import { Banner, BlockStack, InlineGrid, List, Modal, Select, Text, TextField } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import { codFormApi, parseError } from "../api";
import useResource from "../useResource";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { newOffer, withOfferDefaults } from "../defaults";
import { PATHS } from "../constants";
import { setIn, toInt } from "../utils";
import { t } from "../i18n";
import Gate from "../components/Gate";
import Screen, { SaveErrorBanner } from "../components/Screen";
import ScreenSaveBar from "../components/ScreenSaveBar";
import OfferTargetingCard from "./OfferTargetingCard";
import { offerMeta, statusLabel } from "./offerMeta";

const toLocalInput = (iso) => {
  if (!iso) return "";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  const pad = (number) => String(number).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};
const fromLocalInput = (text) => {
  if (!text) return null;
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
};

/**
 * Frame shared by the five offer editors: load / create / update, name,
 * status with the client-side limits, priority, schedule, targeting, delete.
 * `children({offer, config, setConfig, bootstrap})` renders the type's own fields;
 * `validate(offer)` returns a list of problems that block saving.
 */
const OfferEditorShell = ({ segment, id, validate, children, hideTargeting }) => {
  const meta = offerMeta(segment);
  const bootstrap = useCodFormBootstrap();
  const isNew = !id || id === "new";
  const [siblings, setSiblings] = useState([]);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [showProblems, setShowProblems] = useState(false);
  // Leaving closes the save bar first: the app blocks navigation while it is open.
  const [leaveTo, setLeaveTo] = useState(null);

  useEffect(() => {
    if (!leaveTo) return undefined;
    const timer = setTimeout(() => navigateTo(leaveTo), 60);
    return () => clearTimeout(timer);
  }, [leaveTo]);

  const resource = useResource({
    load: () => (isNew ? Promise.resolve(newOffer(meta.offerType)) : codFormApi.offers.show(id)),
    save: (offer) => {
      const { id: offerId, ab_test_id: _abTestId, ...body } = offer;
      return isNew ? codFormApi.offers.create(body) : codFormApi.offers.update(offerId || id, body);
    },
    prepare: withOfferDefaults,
    deps: [segment, id],
  });
  const { data, setData, isDirty, loading, saving, error, saveError, save, discard, reload, clearSaveError } = resource;

  useEffect(() => {
    codFormApi.offers
      .index(meta.offerType)
      .then((response) => setSiblings((response && response.items) || []))
      .catch(() => setSiblings([]));
  }, [meta.offerType]);

  const others = useMemo(() => siblings.filter((offer) => String(offer.id) !== String(id)), [siblings, id]);
  const activeOthers = others.filter((offer) => offer.status === "active");
  const atLimit = meta.activeLimit != null && activeOthers.length >= meta.activeLimit;

  // OFF-2: a product belongs to at most one active quantity offer.
  const overlapNames = useMemo(() => {
    if (!data || meta.offerType !== "quantity" || data.status !== "active") return [];
    const mine = data.targeting || {};
    return activeOthers
      .filter((offer) => {
        const theirs = offer.targeting || {};
        if (mine.scope !== "selected" || theirs.scope !== "selected") return mine.scope === "all" && theirs.scope === "all";
        return (theirs.product_ids || []).some((productId) => (mine.product_ids || []).includes(productId));
      })
      .map((offer) => offer.name);
  }, [data, activeOthers, meta.offerType]);

  const problems = useMemo(() => {
    if (!data) return [];
    const list = [];
    if (!data.name || data.name.trim() === "") list.push(t("offers.error_name", "Give the offer a name."));
    const targeting = data.targeting || {};
    if (targeting.scope === "selected" && (targeting.product_ids || []).length === 0 && (targeting.collection_ids || []).length === 0) {
      list.push(t("offers.targeting_empty", "Select at least one product or collection, or choose all products."));
    }
    if (data.status === "active" && atLimit) list.push(meta.limitText);
    if (overlapNames.length > 0) {
      list.push(t("offers.overlap_error", "A product can be in only one active quantity offer. Some of these products are already in another active offer."));
    }
    if (data.starts_at && data.ends_at && new Date(data.starts_at) >= new Date(data.ends_at)) {
      list.push(t("offers.error_schedule", "The end must be after the start."));
    }
    return list.concat(validate ? validate(data) : []);
  }, [data, atLimit, overlapNames, validate, meta.limitText]);

  const setConfig = useCallback(
    (key, value) => setData((current) => setIn(current, ["config", key], value)),
    [setData],
  );

  const handleSave = async () => {
    if (problems.length > 0) {
      setShowProblems(true);
      return;
    }
    setShowProblems(false);
    const ok = await save();
    if (ok && isNew) setLeaveTo(`${PATHS.offers}/${segment}`);
  };

  const remove = () => {
    setDeleting(true);
    codFormApi.offers
      .destroy(id)
      .then(() => {
        setConfirmDelete(false);
        setLeaveTo(`${PATHS.offers}/${segment}`);
      })
      .catch(() => setDeleting(false));
  };

  const inTest = !!(data && data.ab_test_id);

  return (
    <Screen
      title={isNew ? meta.newLabel : (data && data.name) || meta.title}
      backPath={`${PATHS.offers}/${segment}`}
      backLabel={meta.title}
      secondaryActions={
        isNew ? undefined : [{ content: t("common.delete", "Delete"), destructive: true, onAction: () => setConfirmDelete(true), disabled: inTest }]
      }
      loading={loading || !data}
      error={error}
      onRetry={reload}
    >
      <Gate feature={meta.feature} title={meta.title}>
        {data && (
          <>
            <ScreenSaveBar
              open={(isDirty || isNew) && !leaveTo}
              saving={saving}
              onSave={handleSave}
              onDiscard={isNew ? () => setLeaveTo(`${PATHS.offers}/${segment}`) : discard}
            />
            <SaveErrorBanner error={saveError} onDismiss={clearSaveError} />
            {showProblems && problems.length > 0 && (
              <Banner tone="critical" title={t("offers.problems_title", "Fix these before saving")} onDismiss={() => setShowProblems(false)}>
                <List type="bullet">
                  {problems.map((problem, index) => (
                    <List.Item key={index}>{problem}</List.Item>
                  ))}
                </List>
              </Banner>
            )}
            {inTest && (
              <Banner tone="info">
                <p>{t("offers.in_ab_test", "This offer is part of a running A/B test. Stop the test before deleting it.")}</p>
              </Banner>
            )}

            <SectionCard title={t("offers.basics_title", "Offer")}>
              <BlockStack gap="400">
                <TextField
                  label={t("offers.name", "Name")}
                  value={data.name || ""}
                  onChange={(value) => setData((current) => ({ ...current, name: value }))}
                  helpText={t("offers.name_help", "Only you see this name.")}
                  maxLength={80}
                  autoComplete="off"
                />
                <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                  <Select
                    label={t("offers.status", "Status")}
                    options={["draft", "active", "paused"].map((status) => ({
                      value: status,
                      label: statusLabel(status),
                      disabled: status === "active" && atLimit && data.status !== "active",
                    }))}
                    value={data.status === "archived" ? "paused" : data.status || "draft"}
                    onChange={(value) => setData((current) => ({ ...current, status: value }))}
                    helpText={atLimit ? meta.limitText : undefined}
                  />
                  <TextField
                    label={t("offers.priority", "Priority")}
                    type="number"
                    min={0}
                    value={String(data.priority == null ? 0 : data.priority)}
                    onChange={(value) => setData((current) => ({ ...current, priority: Math.max(0, toInt(value, 0)) }))}
                    helpText={t("offers.priority_help", "When several offers match, the lowest number wins.")}
                    autoComplete="off"
                  />
                  <TextField
                    label={t("offers.starts_at", "Starts (optional)")}
                    type="datetime-local"
                    value={toLocalInput(data.starts_at)}
                    onChange={(value) => setData((current) => ({ ...current, starts_at: fromLocalInput(value) }))}
                    autoComplete="off"
                  />
                  <TextField
                    label={t("offers.ends_at", "Ends (optional)")}
                    type="datetime-local"
                    value={toLocalInput(data.ends_at)}
                    onChange={(value) => setData((current) => ({ ...current, ends_at: fromLocalInput(value) }))}
                    autoComplete="off"
                  />
                </InlineGrid>
              </BlockStack>
            </SectionCard>

            {children({ offer: data, config: data.config || {}, setConfig, setData, bootstrap })}

            {!hideTargeting && (
              <OfferTargetingCard
                targeting={data.targeting}
                onChange={(targeting) => setData((current) => ({ ...current, targeting }))}
                error={saveError && saveError.errors && saveError.errors.targeting}
                overlapNames={overlapNames}
              />
            )}
          </>
        )}
      </Gate>

      <Modal
        open={confirmDelete}
        onClose={() => setConfirmDelete(false)}
        title={t("offers.delete_title", "Delete this offer?")}
        primaryAction={{ content: t("common.delete", "Delete"), destructive: true, onAction: remove, loading: deleting }}
        secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: () => setConfirmDelete(false) }]}
      >
        <Modal.Section>
          <Text as="p">{t("offers.delete_body", "Buyers will no longer see it. This cannot be undone.")}</Text>
        </Modal.Section>
      </Modal>
    </Screen>
  );
};

export default OfferEditorShell;

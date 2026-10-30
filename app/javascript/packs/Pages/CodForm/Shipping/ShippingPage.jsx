import React, { useCallback, useEffect, useState } from "react";
import { Badge, Banner, BlockStack, Button, Card, Checkbox, InlineStack, Modal, Pagination, Text } from "@shopify/polaris";
import { EditMinor, DeleteMinor } from "@shopify/polaris-icons";
import { codFormApi, parseError } from "../api";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { LIMITS, PATHS, countryName } from "../constants";
import { newShippingRate } from "../defaults";
import { formatMoney } from "../money";
import { moveItem } from "../utils";
import { navigateTo } from "../../../../utils/navigate";
import { t } from "../i18n";
import Screen, { SaveErrorBanner } from "../components/Screen";
import EmptyState from "../components/EmptyState";
import SortableList from "../Designer/SortableList";
import RateModal from "./RateModal";
import CsvImportModal from "./CsvImportModal";

const summarize = (rate, money) => {
  const conditions = rate.conditions || {};
  const parts = [];
  if ((conditions.countries || []).length) {
    const names = conditions.countries.slice(0, 3).map(countryName).join(", ");
    parts.push(conditions.countries.length > 3 ? `${names} +${conditions.countries.length - 3}` : names);
  }
  if ((conditions.provinces || []).length) {
    parts.push(t("shipping.summary_provinces", "%{count} provinces", { count: conditions.provinces.length }));
  }
  if (conditions.subtotal_min_cents != null || conditions.subtotal_max_cents != null) {
    parts.push(
      t("shipping.summary_total", "Subtotal %{min} – %{max}", {
        min: conditions.subtotal_min_cents != null ? money(conditions.subtotal_min_cents) : "0",
        max: conditions.subtotal_max_cents != null ? money(conditions.subtotal_max_cents) : "∞",
      }),
    );
  }
  if (conditions.weight_min_grams != null || conditions.weight_max_grams != null) {
    parts.push(
      t("shipping.summary_weight", "Weight %{min} – %{max} g", {
        min: conditions.weight_min_grams != null ? conditions.weight_min_grams : 0,
        max: conditions.weight_max_grams != null ? conditions.weight_max_grams : "∞",
      }),
    );
  }
  if (conditions.quantity_min != null || conditions.quantity_max != null) {
    parts.push(
      t("shipping.summary_quantity", "Quantity %{min} – %{max}", {
        min: conditions.quantity_min != null ? conditions.quantity_min : 0,
        max: conditions.quantity_max != null ? conditions.quantity_max : "∞",
      }),
    );
  }
  if (conditions.products && conditions.products.mode && conditions.products.mode !== "any") {
    parts.push(
      conditions.products.mode === "only"
        ? t("shipping.summary_products_only", "Selected products only")
        : t("shipping.summary_products_exclude", "Some products excluded"),
    );
  }
  return parts.length ? parts.join(" · ") : t("shipping.summary_always", "Always offered");
};

/** /features/cod-form/shipping — rate table, conditions, free shipping, CSV import, reorder. */
const ShippingPage = () => {
  const bootstrap = useCodFormBootstrap();
  const [rates, setRates] = useState(null);
  const [error, setError] = useState(null);
  const [actionError, setActionError] = useState(null);
  const [modalError, setModalError] = useState(null);
  const [editing, setEditing] = useState(null);
  const [saving, setSaving] = useState(false);
  const [importing, setImporting] = useState(false);
  const [deleting, setDeleting] = useState(null);
  const [busy, setBusy] = useState(false);
  const [page, setPage] = useState(0);

  const money = (cents) => formatMoney(cents, bootstrap && bootstrap.moneyFormat, bootstrap && bootstrap.currency);

  const load = useCallback(() => {
    setError(null);
    return codFormApi.shippingRates
      .index()
      .then((response) => {
        const items = ((response && response.items) || []).slice().sort((a, b) => (a.position || 0) - (b.position || 0));
        setRates(items);
      })
      .catch((err) => setError(parseError(err)));
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const saveRate = (rate) => {
    setSaving(true);
    setModalError(null);
    const { id, ...body } = rate;
    const request = id ? codFormApi.shippingRates.update(id, body) : codFormApi.shippingRates.create(body);
    request
      .then(() => {
        setEditing(null);
        return load();
      })
      .catch((err) => setModalError(parseError(err)))
      .then(() => setSaving(false));
  };

  const toggleActive = (rate, active) => {
    setRates((current) => current.map((item) => (item.id === rate.id ? { ...item, active } : item)));
    const { id, ...body } = rate;
    codFormApi.shippingRates.update(id, { ...body, active }).catch((err) => {
      setActionError(parseError(err));
      load();
    });
  };

  const reorder = (from, to) => {
    const next = moveItem(rates, from, to);
    setRates(next);
    setBusy(true);
    codFormApi.shippingRates
      .reorder(next.map((rate) => rate.id))
      .catch((err) => {
        setActionError(parseError(err));
        return load();
      })
      .then(() => setBusy(false));
  };

  const remove = () => {
    const rate = deleting;
    setBusy(true);
    codFormApi.shippingRates
      .destroy(rate.id)
      .then(() => load())
      .catch((err) => setActionError(parseError(err)))
      .then(() => {
        setBusy(false);
        setDeleting(null);
      });
  };

  const list = rates || [];
  const pages = Math.max(1, Math.ceil(list.length / LIMITS.SHIPPING_PAGE_SIZE));
  const currentPage = Math.min(page, pages - 1);
  const offset = currentPage * LIMITS.SHIPPING_PAGE_SIZE;
  const visible = list.slice(offset, offset + LIMITS.SHIPPING_PAGE_SIZE);
  const noActive = list.length > 0 && !list.some((rate) => rate.active !== false);

  return (
    <Screen
      title={t("shipping.title", "Shipping rates")}
      backPath={PATHS.advanced}
      backLabel={t("setup.advanced_settings_title", "Advanced settings")}
      subtitle={t("shipping.subtitle", "The delivery options and prices buyers see in the COD Form.")}
      primaryAction={{ content: t("shipping.add_rate", "Add shipping rate"), onAction: () => { setModalError(null); setEditing(newShippingRate(null)); } }}
      secondaryActions={[{ content: t("shipping.import_csv", "Import rates from CSV"), onAction: () => setImporting(true) }]}
      loading={rates === null && !error}
      error={error}
      onRetry={load}
    >
      <SaveErrorBanner error={actionError} onDismiss={() => setActionError(null)} />
      {noActive && (
        <Banner tone="warning">
          <p>{t("shipping.none_active", "No rate is active, so buyers cannot complete the form. Turn on at least one rate.")}</p>
        </Banner>
      )}

      {list.length === 0 ? (
        <EmptyState
          heading={t("shipping.empty_title", "Add your first shipping rate")}
          action={{ content: t("shipping.add_rate", "Add shipping rate"), onAction: () => setEditing(newShippingRate(null)) }}
          secondaryAction={{ content: t("shipping.import_csv", "Import rates from CSV"), onAction: () => setImporting(true) }}
        >
          <p>{t("shipping.empty_body", "The form uses its own rate table. Add a rate with a name and a price; for free shipping set the price to 0. Buyers cannot order until a rate matches their address.")}</p>
        </EmptyState>
      ) : (
        <Card>
          <BlockStack gap="200">
            <InlineStack align="space-between" blockAlign="center">
              <Text as="h2" variant="headingMd">
                {t("shipping.rates_count", "%{count} rates", { count: list.length })}
              </Text>
              <Text as="span" variant="bodySm" tone="subdued">
                {t("shipping.order_help", "Shown to buyers in this order. The first matching rate is preselected.")}
              </Text>
            </InlineStack>
            <SortableList
              items={visible}
              getKey={(rate) => rate.id}
              onReorder={(from, to) => reorder(offset + from, offset + to)}
              isLocked={() => busy}
              renderItem={(rate) => (
                <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
                  <BlockStack gap="050">
                    <InlineStack gap="200" blockAlign="center" wrap>
                      <Text as="span" variant="bodyMd" fontWeight="semibold">
                        {rate.name}
                      </Text>
                      {Number(rate.price_cents) === 0 ? (
                        <Badge tone="success">{t("shipping.free", "Free shipping")}</Badge>
                      ) : (
                        <Text as="span" variant="bodyMd">
                          {formatMoney(rate.price_cents, rate.currency ? "" : bootstrap && bootstrap.moneyFormat, rate.currency || (bootstrap && bootstrap.currency))}
                        </Text>
                      )}
                      {rate.source === "csv" && <Badge>{t("shipping.source_csv", "CSV")}</Badge>}
                      {rate.active === false && <Badge>{t("common.disabled", "Off")}</Badge>}
                    </InlineStack>
                    {rate.description ? (
                      <Text as="span" variant="bodySm" tone="subdued">
                        {rate.description}
                      </Text>
                    ) : null}
                    <Text as="span" variant="bodySm" tone="subdued">
                      {summarize(rate, money)}
                    </Text>
                  </BlockStack>
                  <InlineStack gap="200" blockAlign="center" wrap={false}>
                    <Checkbox
                      label={t("shipping.active", "Active")}
                      checked={rate.active !== false}
                      onChange={(value) => toggleActive(rate, value)}
                    />
                    <Button icon={EditMinor} accessibilityLabel={t("common.edit", "Edit")} onClick={() => { setModalError(null); setEditing(rate); }} />
                    <Button icon={DeleteMinor} tone="critical" accessibilityLabel={t("common.delete", "Delete")} onClick={() => setDeleting(rate)} />
                  </InlineStack>
                </InlineStack>
              )}
            />
            {pages > 1 && (
              <InlineStack align="center">
                <Pagination
                  hasPrevious={currentPage > 0}
                  hasNext={currentPage < pages - 1}
                  onPrevious={() => setPage(currentPage - 1)}
                  onNext={() => setPage(currentPage + 1)}
                  label={t("common.page_of", "Page %{page} of %{pages}", { page: currentPage + 1, pages })}
                />
              </InlineStack>
            )}
          </BlockStack>
        </Card>
      )}

      <Card>
        <BlockStack gap="200">
          <Text as="h3" variant="headingSm">
            {t("shipping.no_rate_title", "When no rate matches")}
          </Text>
          <Text as="p" tone="subdued">
            {t("shipping.no_rate_message", "The buyer sees \"We don't deliver to this address yet.\" and cannot submit. You can change that text in Form designer, under Texts.")}
          </Text>
          <InlineStack>
            <Button onClick={() => navigateTo(PATHS.designer)}>{t("shipping.open_designer", "Open Form designer")}</Button>
          </InlineStack>
        </BlockStack>
      </Card>

      <RateModal
        open={!!editing}
        rate={editing}
        currency={bootstrap && bootstrap.currency}
        saving={saving}
        error={modalError}
        onClose={() => setEditing(null)}
        onSave={saveRate}
      />
      <CsvImportModal open={importing} onClose={() => setImporting(false)} onImported={load} />
      <Modal
        open={!!deleting}
        onClose={() => setDeleting(null)}
        title={t("shipping.delete_title", "Delete this rate?")}
        primaryAction={{ content: t("common.delete", "Delete"), destructive: true, onAction: remove, loading: busy }}
        secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: () => setDeleting(null) }]}
      >
        <Modal.Section>
          <Text as="p">{t("shipping.delete_body", "\"%{name}\" will no longer be offered in the form.", { name: deleting ? deleting.name : "" })}</Text>
        </Modal.Section>
      </Modal>
    </Screen>
  );
};

export default ShippingPage;

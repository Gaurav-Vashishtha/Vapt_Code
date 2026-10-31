import React, { useCallback, useContext, useEffect, useMemo, useState } from "react";
import {
  Card,
  BlockStack,
  Box,
  Text,
  InlineStack,
  Badge,
  Banner,
  Select,
  Button,
  Spinner,
  Divider,
  EmptyState,
  Modal,
  TextField,
  Checkbox,
} from "@shopify/polaris";
import useApi from "../../Hooks/useApi";
import Api from "../../Services/Api";
import { StoreContext } from "../../Context/Store";
import NewAutomationWizard from "./NewAutomationWizard";
import TestAutomationModal from "./TestAutomationModal";

import I18n from "../../i18n-lang";
const STAGED_EVENT_KEYS = ["abandoned_cart", "cart_abandoned", "browse_abandoned"];

// COD→prepaid timing and discounts live in setting.prepaid_reminders — the same
// list the Prepaid settings page edits — because the prepaid scheduler fans out
// one send per matching reminder rather than going through DispatchEventJob.
// The binding stays as the default template for reminders that don't name one.
const PREPAID_EVENT_KEY = "cod_to_prepaid";

// Pull {{N}} placeholders out of a body text in numerical order, deduped.
const extractPositions = (text) => {
  if (!text) return [];
  const seen = new Set();
  (text.match(/\{\{(\d+)\}\}/g) || []).forEach((m) =>
    seen.add(m.replace(/[{}]/g, ""))
  );
  return Array.from(seen).sort((a, b) => Number(a) - Number(b));
};

// Body text from a template's serialized components, if present.
const bodyTextOf = (template) => {
  const body = (template?.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "BODY"
  );
  return body?.text || "";
};

// The template's HEADER component, if any.
const headerComponentOf = (template) =>
  (template?.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "HEADER"
  );

// True when the template has an IMAGE header but no send-usable media source
// configured yet (no product-image mode, media id, or URL). Synced-from-Meta
// templates arrive like this — we must collect a header image at bind time or
// the send falls back to a link Meta can't fetch (error 131053).
const imageHeaderNeedsConfig = (template) => {
  const header = headerComponentOf(template);
  if (!header || (header.format || "").toUpperCase() !== "IMAGE") return false;
  const hm = template?.headerMedia || {};
  const configured =
    !!hm.mediaId ||
    !!hm.media_id ||
    !!hm.url ||
    hm.mode === "order_product_image" ||
    (hm.source === "url" && !!hm.value);
  return !configured;
};

// True when the template is missing a mapping for at least one {{N}} position,
// or when its existing mapping references a variable not defined on this event
// (e.g. it was originally authored against `order_fulfilled` and is now being
// bound to `order_created`).
const needsMappingConfirmation = (template, event) => {
  if (!template || !event) return false;

  // A dynamic URL button with no link variable configured must be set up before
  // binding, else the send fails with Meta 131008 (missing button parameter).
  if (hasDynamicUrlButton(template) && !template?.urlButton?.variable) return true;

  // An IMAGE-header template with no header image configured must be set up
  // before binding, else the send fails with Meta 131053 (media upload error).
  if (imageHeaderNeedsConfig(template)) return true;

  const positions = extractPositions(bodyTextOf(template));
  if (positions.length === 0) return false;
  const eventVarKeys = new Set((event.variables || []).map((v) => v.key));
  const mapping = template.variableMapping || {};
  return positions.some((p) => {
    const key = mapping[p];
    return !key || !eventVarKeys.has(key);
  });
};

const WhatsappEventMappings = () => {
  const [error, setError] = useState(null);
  const [wizardOpen, setWizardOpen] = useState(false);
  // Holds { eventTypeKey, binding } when a Test modal is open, null when closed.
  const [testing, setTesting] = useState(null);
  // Holds { event, template } when the merchant picked a template whose
  // variable mapping doesn't fully cover this event — we open a modal asking
  // them to confirm before binding.
  const [confirmingMapping, setConfirmingMapping] = useState(null);

  // WhatsApp notifications are a paid feature: only plans whose name contains
  // "enterprise" or "india_budget" (Enterprise, Enterprise Plus, India Budget)
  // may turn a notification on. Everyone else gets disabled controls + an
  // upgrade prompt. Exception: shops in the WHATSAPP_BSP_PLAN_EXEMPT_DOMAINS env
  // allowlist (shop.whatsapp_bsp_exempt) bypass the plan check entirely.
  // StoreContext defaults to null, hence the `|| {}` guard.
  const { plan: [plan] = [], shop: [shop] = [] } = useContext(StoreContext) || {};
  const canUseNotifications = useMemo(() => {
    if (shop?.whatsapp_bsp_exempt === true) return true;
    const name = (plan?.name || "").toLowerCase();
    return name.includes("enterprise") || name.includes("india_budget") || name.includes("rabbit");
  }, [plan, shop]);
  const goToBilling = useCallback(() => {
    window.history.pushState({}, "", "/subscription");
    window.dispatchEvent(new PopStateEvent("popstate"));
  }, []);

  const [{ data: eventsData, loading: loadingEvents }] = useApi(
    { url: "/api/whatsapp/events", method: "GET" },
    { manual: false }
  );
  // all=1: templates across every connected number, each tagged with its
  // number, so a notification can be routed to a template on any number.
  const [{ data: templatesData, loading: loadingTemplates }, refetchTemplates] = useApi(
    { url: "/api/whatsapp/templates", method: "GET", params: { all: 1 } },
    { manual: false }
  );
  const [{ data: bindingsData, loading: loadingBindings }, refetchBindings] = useApi(
    { url: "/api/whatsapp/template_bindings", method: "GET" },
    { manual: false }
  );
  const [, postBinding] = useApi(
    { url: "/api/whatsapp/template_bindings", method: "POST" },
    { manual: true }
  );
  const patchTemplate = useCallback(
    (id, data) =>
      Api.patch(
        `https://${process.env.APP_HOST}/api/whatsapp/templates/${id}`,
        data
      ),
    []
  );
  const deleteBinding = useCallback(
    (id) =>
      Api.delete(
        `https://${process.env.APP_HOST}/api/whatsapp/template_bindings/${id}`
      ),
    []
  );

  // Refresh when a new template is created via the sibling tab.
  useEffect(() => {
    const handler = () => refetchTemplates();
    window.addEventListener("whatsapp:template-created", handler);
    return () => window.removeEventListener("whatsapp:template-created", handler);
  }, [refetchTemplates]);

  // Automations are per-trigger (order placed, shipped, OTP, …). Campaign
  // broadcasts are sent manually from the Campaigns flow, not bound here, so
  // they're excluded from the automations list.
  const events = (eventsData?.events || []).filter((e) => e.kind !== "campaign");
  const templates = templatesData?.templates || [];
  const bindings = bindingsData?.bindings || [];

  // Single-binding lookup for non-staged events (everything except
  // abandoned_cart). For abandoned_cart we use `stagesByEvent` below — N
  // bindings sorted by stage_index.
  const bindingByEvent = useMemo(() => {
    const map = {};
    bindings
      .filter((b) => (b.stageIndex || 0) === 0)
      .forEach((b) => {
        // Keep only the first stage_index=0 binding per event (other events
        // never have multiple stages — this is just defensive).
        map[b.eventTypeKey] ||= b;
      });
    return map;
  }, [bindings]);

  // All bindings per staged event, sorted by stage_index, so the
  // multi-stage editor can render rows in display order.
  const stagesByEvent = useMemo(() => {
    const map = {};
    bindings.forEach((b) => {
      (map[b.eventTypeKey] ||= []).push(b);
    });
    Object.values(map).forEach((arr) =>
      arr.sort((a, b) => (a.stageIndex || 0) - (b.stageIndex || 0))
    );
    return map;
  }, [bindings]);

  // Templates bindable to each event: approved templates already assigned to
  // the event, PLUS existing approved templates not yet tied to any event whose
  // category matches one of the event's bindable categories (these get
  // "adopted" into the event on bind). Some events accept multiple categories
  // (e.g. abandoned_cart accepts UTILITY and MARKETING) — they expose those
  // via `bindableCategories`.
  const bindableByEvent = useMemo(() => {
    const map = {};
    events.forEach((ev) => {
      const allowed = (
        ev.bindableCategories ||
        (ev.templateCategory ? [ev.templateCategory] : [])
      ).map((c) => (c || "").toUpperCase());
      map[ev.key] = templates.filter(
        (t) =>
          t.status === "approved" &&
          (t.eventTypeKey === ev.key ||
            (!t.eventTypeKey && allowed.includes((t.category || "").toUpperCase())))
      );
    });
    return map;
  }, [events, templates]);

  // Actually post the binding — used both directly (mapping is already fine)
  // and after the merchant confirms a fresh mapping in the modal. Accepts
  // the full per-stage payload so multi-stage editors can use it too.
  const finalizeBind = async (eventKey, templateId, opts = {}) => {
    await postBinding({
      data: {
        event_type_key: eventKey,
        whatsapp_template_id: templateId,
        stage_index: opts.stageIndex ?? 0,
        offset_minutes: opts.offsetMinutes ?? 0,
        ...(opts.discountConfig ? { discount_config: opts.discountConfig } : {}),
      },
    });
    await Promise.all([refetchBindings(), refetchTemplates()]);
  };

  const handleBind = async (eventKey, templateId, opts = {}) => {
    setError(null);
    // Hard gate: never let a non-qualifying plan flip a notification on, even if
    // a control slips through. All three enable paths (BindingRow, the staged
    // editor, and the mapping-confirm modal) pass through here first.
    if (!canUseNotifications) {
      const msg =
        "Turning on WhatsApp notifications requires the Enterprise or India Budget plan. Upgrade to enable.";
      setError(msg);
      throw new Error(msg);
    }
    try {
      const event = events.find((e) => e.key === eventKey);
      const template = templates.find((t) => t.id === templateId);

      // A discount is configured but the template doesn't yet map a discount.*
      // variable — open the picker so they choose which placeholder shows the
      // code (otherwise the backend rejects the bind and the code never shows).
      const discountConfigured =
        opts.discountConfig && (opts.discountConfig.mode || "none") !== "none";
      const mapsDiscount = Object.values(template?.variableMapping || {}).some(
        (v) => String(v).startsWith("discount.")
      );

      // If the template's body has placeholders the merchant hasn't tied to
      // this event's variables (common when picking a template originally
      // created for another event), or a discount needs mapping, pause and let
      // them resolve the mapping before we actually flip the binding.
      if (needsMappingConfirmation(template, event) || (discountConfigured && !mapsDiscount)) {
        setConfirmingMapping({ event, template, opts });
        return;
      }
      await finalizeBind(eventKey, templateId, opts);
    } catch (err) {
      const msg = err?.response?.data?.error || err?.message || "Failed to set binding";
      setError(msg); // page-level banner (top of page)
      // Rethrow so callers near the action (e.g. the abandoned-cart stage row)
      // can surface it inline too — the top banner is easy to miss when scrolled.
      throw new Error(msg);
    }
  };

  const handleMappingConfirmed = async ({ variableMapping, urlButton, headerMedia }) => {
    if (!confirmingMapping) return;
    setError(null);
    try {
      await patchTemplate(confirmingMapping.template.id, {
        event_type_key: confirmingMapping.event.key,
        variable_mapping: variableMapping,
        // Persist the URL button's link variable so UrlButtonResolver can fill
        // the {{1}} button param at send time (otherwise Meta returns 131008).
        ...(urlButton ? { url_button: urlButton } : {}),
        // Persist the chosen header image (product image or a fixed URL) so the
        // send has a usable media source instead of a link Meta can't fetch.
        ...(headerMedia ? { header_media: headerMedia } : {}),
      });
      await finalizeBind(
        confirmingMapping.event.key,
        confirmingMapping.template.id,
        confirmingMapping.opts || {}
      );
      setConfirmingMapping(null);
    } catch (err) {
      setError(err?.response?.data?.error || err?.message || "Failed to save mapping");
    }
  };

  const handleUnbind = async (bindingId) => {
    if (!window.confirm("Stop using this template for this event?")) return;
    setError(null);
    try {
      await deleteBinding(bindingId);
      await refetchBindings();
    } catch (err) {
      setError(err?.response?.data?.error || err?.message || "Failed to unbind");
    }
  };

  const loading = loadingEvents || loadingTemplates || loadingBindings;

  if (loading && !events.length) {
    return (
      <Card padding="600">
          <InlineStack gap="200" align="center">
            <Spinner size="small" />
            <Text as="span">{I18n.t("whatsapp_event_mappings.loading_events")}</Text>
          </InlineStack>
        
      </Card>
    );
  }

  return (
    <BlockStack gap="400">
      {error && (
        <Banner tone="critical" onDismiss={() => setError(null)}>
          {error}
        </Banner>
      )}
      {canUseNotifications ? (
        <Banner tone="info">
          {I18n.t("whatsapp_event_mappings.set_up_a")} <strong>{I18n.t("whatsapp_event_mappings.notification")}</strong> {I18n.t("whatsapp_event_mappings.for_each_customer_moment_when_an")}
        </Banner>
      ) : (
        <Banner
          tone="warning"
          title={I18n.t("whatsapp_event_mappings.whatsapp_notifications_need_an_upgrade")}
          action={{
            content: I18n.t("whatsapp_event_mappings.upgrade_plan"),
            onAction: goToBilling,
          }}
        >
          {I18n.t("whatsapp_event_mappings.notifications_need_upgrade_body", {
            enterprise: I18n.t("whatsapp_event_mappings.enterprise"),
            india: I18n.t("whatsapp_event_mappings.india_budget"),
          })}
        </Banner>
      )}

      {canUseNotifications && (
        <InlineStack align="end">
          <Button variant="primary" onClick={() => setWizardOpen(true)}>
            {I18n.t("whatsapp_event_mappings.new_notification")}
          </Button>
        </InlineStack>
      )}

      <NewAutomationWizard
        open={wizardOpen}
        onClose={() => setWizardOpen(false)}
        onCreated={() => refetchBindings()}
      />

      <TestAutomationModal
        open={!!testing}
        eventTypeKey={testing?.eventTypeKey}
        stageIndex={testing?.stageIndex || 0}
        binding={testing?.binding}
        template={testing?.template}
        event={testing?.event}
        onClose={() => setTesting(null)}
      />

      {confirmingMapping && (
        <ConfirmMappingModal
          event={confirmingMapping.event}
          template={confirmingMapping.template}
          editing={confirmingMapping.editing}
          onCancel={() => setConfirmingMapping(null)}
          onConfirm={handleMappingConfirmed}
        />
      )}

      {events.map((event) => {
        const binding = bindingByEvent[event.key];
        const approved = bindableByEvent[event.key] || [];
        const isStaged = STAGED_EVENT_KEYS.includes(event.key);
        const stages = stagesByEvent[event.key] || [];

        return (
          <Card key={event.key} padding="600">
              <BlockStack gap="300">
                <InlineStack align="space-between" blockAlign="start" wrap>
                  <BlockStack gap="100">
                    <Text as="h3" variant="headingMd">
                      {event.label}
                    </Text>
                    <Text as="p" tone="subdued" variant="bodySm">
                      {event.description}
                    </Text>
                  </BlockStack>
                  <InlineStack gap="200" blockAlign="center">
                    {stages.some((b) => b.paused) ? (
                      <Badge tone="warning">
                        {I18n.t("whatsapp_event_mappings.pause_badge", { defaultValue: "Paused" })}
                      </Badge>
                    ) : isStaged ? (
                      stages.length > 0 ? (
                        <Badge tone="success">
                          {I18n.t("whatsapp_event_mappings.active_reminders", {
                            count: stages.length,
                          })}
                        </Badge>
                      ) : (
                        <Badge>{I18n.t("whatsapp_event_mappings.not_set_up")}</Badge>
                      )
                    ) : binding ? (
                      <Badge tone="success">
                          {I18n.t("whatsapp_event_mappings.active_sends_template", {
                            template: binding.templateName,
                          })}
                        </Badge>
                    ) : (
                      <Badge>{I18n.t("whatsapp_event_mappings.not_set_up")}</Badge>
                    )}
                    {stages.length > 0 && stages[0].pausable !== false && (
                      <NotificationPauseButton
                        eventKey={event.key}
                        paused={stages.some((b) => b.paused)}
                        disabled={!canUseNotifications && !stages.some((b) => !b.paused)}
                        onChanged={() => refetchBindings()}
                        onError={setError}
                      />
                    )}
                  </InlineStack>
                </InlineStack>

                <Divider />

                {approved.length === 0 ? (
                  <Box padding="200">
                    <Text as="p" tone="subdued" variant="bodySm">
                      {I18n.t("whatsapp_event_mappings.no_template_ready_yet")}{" "}
                      <a href="#" onClick={(e) => { e.preventDefault(); window.dispatchEvent(new CustomEvent("whatsapp:goto-tab", { detail: "library" })); }}>
                        {I18n.t("whatsapp_event_mappings.pick_a_pre_made_template")}
                      </a>{" "}
                      {I18n.t("whatsapp_event_mappings.or")}{" "}
                      <a href="#" onClick={(e) => { e.preventDefault(); window.dispatchEvent(new CustomEvent("whatsapp:goto-tab", { detail: "create" })); }}>
                        {I18n.t("whatsapp_event_mappings.write_your_own")}
                      </a>
                      {I18n.t("whatsapp_event_mappings.approves_within_hours")}
                    </Text>
                  </Box>
                ) : isStaged ? (
                  <AbandonedCartStagesEditor
                    event={event}
                    approved={approved}
                    stages={stages}
                    gated={!canUseNotifications}
                    onUpgrade={goToBilling}
                    onSaveStage={(s) =>
                      handleBind(event.key, s.whatsappTemplateId, {
                        stageIndex: s.stageIndex,
                        offsetMinutes: s.offsetMinutes,
                        discountConfig: s.discountConfig,
                      })
                    }
                    onRemoveStage={(id) => handleUnbind(id)}
                    onTest={(stage) =>
                      setTesting({
                        eventTypeKey: event.key,
                        binding: stage,
                        event,
                        stageIndex: stage?.stageIndex || 0,
                        template: templates.find(
                          (t) => t.id === stage?.whatsappTemplateId
                        ),
                      })
                    }
                  />
                ) : (
                  <BlockStack gap="300">
                    <BindingRow
                      event={event}
                      approved={approved}
                      binding={binding}
                      gated={!canUseNotifications}
                      onUpgrade={goToBilling}
                      onBind={(tid, offsetMinutes) =>
                        handleBind(event.key, tid, {
                          offsetMinutes: offsetMinutes ?? 0,
                        })
                      }
                      onUnbind={() => handleUnbind(binding.id)}
                      onEditVariables={() =>
                        setConfirmingMapping({
                          event,
                          template: templates.find(
                            (t) => t.id === binding?.whatsappTemplateId
                          ),
                          opts: { offsetMinutes: binding?.offsetMinutes ?? 0 },
                          editing: true,
                        })
                      }
                      onTest={() =>
                        setTesting({
                          eventTypeKey: event.key,
                          binding,
                          event,
                          template: templates.find(
                            (t) => t.id === binding?.whatsappTemplateId
                          ),
                        })
                      }
                    />
                    {event.key === PREPAID_EVENT_KEY && (
                      <>
                        <Divider />
                        <PrepaidRemindersEditor
                          approved={approved}
                          gated={!canUseNotifications}
                          onUpgrade={goToBilling}
                          defaultTemplateName={binding?.templateName}
                        />
                      </>
                    )}
                  </BlockStack>
                )}
              </BlockStack>
            
          </Card>
        );
      })}

      {events.length === 0 && (
        <Card>
          <Box padding="500">
            <EmptyState
              heading={I18n.t("whatsapp_event_mappings.no_events_available")}
              image="https://cdn.shopify.com/s/files/1/0262/4071/2726/files/emptystate-files.png"
            >
              <Text as="p" tone="subdued">
                {I18n.t("whatsapp_event_mappings.the_event_registry_is_empty_check")}
              </Text>
            </EmptyState>
          </Box>
        </Card>
      )}
    </BlockStack>
  );
};

// Asks the merchant to map each {{N}} in the template body to an event
// variable before we flip the binding live. Triggered only when the picked
// template's existing mapping is incomplete or references vars unknown to
// the target event (commonly happens when reusing a template across events
// of the same category).
const escapeHtml = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// Render WhatsApp markdown + fill {{N}} with the chosen variable's sample value
// (highlighted), falling back to the raw {{N}} when a slot isn't mapped yet.
const renderWaLine = (text, fillFor) =>
  escapeHtml(text || "")
    .replace(/```([^`]+)```/g, "<code>$1</code>")
    .replace(/\*([^*\n]+)\*/g, "<strong>$1</strong>")
    .replace(/_([^_\n]+)_/g, "<em>$1</em>")
    .replace(/~([^~\n]+)~/g, "<s>$1</s>")
    .replace(/\{\{(\d+)\}\}/g, (_m, n) => {
      const val = fillFor(n);
      return `<span style="background:#fff3b0;padding:0 3px;border-radius:3px;">${escapeHtml(
        val
      )}</span>`;
    });

// Live WhatsApp-style preview of a template with the merchant's current
// mapping applied, using each event variable's sample value.
const MappingPreview = ({ template, event, mapping }) => {
  const comps = template?.components || [];
  const find = (t) => comps.find((c) => (c?.type || "").toUpperCase() === t);
  const header = find("HEADER");
  const body = find("BODY");
  const footer = find("FOOTER");
  const buttons = find("BUTTONS")?.buttons || [];

  const varByKey = Object.fromEntries(
    (event?.variables || []).map((v) => [v.key, v])
  );
  const fillFor = (n) => {
    const v = mapping[n] ? varByKey[mapping[n]] : null;
    return v ? (v.sample || v.label || `{{${n}}}`) : `{{${n}}}`;
  };

  return (
    <div style={{ background: "#e5ddd5", borderRadius: 8, padding: 12, maxWidth: 340 }}>
      <div
        style={{
          background: "#fff",
          borderRadius: 6,
          padding: "8px 10px",
          fontSize: 13,
          lineHeight: 1.4,
          color: "#111b21",
        }}
      >
        {header && header.format === "TEXT" && (
          <div
            style={{ fontWeight: 700, marginBottom: 6 }}
            dangerouslySetInnerHTML={{ __html: renderWaLine(header.text, fillFor) || "&nbsp;" }}
          />
        )}
        {header && header.format && header.format !== "TEXT" && (
          <div
            style={{
              background: "#e7eef5",
              color: "#445870",
              borderRadius: 4,
              padding: "16px 10px",
              textAlign: "center",
              fontSize: 11,
              marginBottom: 6,
            }}
          >
            {I18n.t("whatsapp_event_mappings.format_preview", {
              format:
                header.format.charAt(0) + header.format.slice(1).toLowerCase(),
            })}
          </div>
        )}
        {body &&
          (body.text || "").split("\n").map((line, i) => (
            <div
              key={i}
              dangerouslySetInnerHTML={{ __html: renderWaLine(line, fillFor) || "&nbsp;" }}
            />
          ))}
        {footer && (
          <div style={{ marginTop: 6, fontSize: 11, color: "#667781" }}>{footer.text}</div>
        )}
        <div style={{ fontSize: 10, color: "#8696a0", textAlign: "right", marginTop: 4 }}>
          {I18n.t("whatsapp_event_mappings.12_34_pm")}
        </div>
      </div>
      {buttons.length > 0 && (
        <div style={{ marginTop: 6, display: "grid", gap: 4 }}>
          {buttons.map((b, idx) => {
            const type = (b.type || "").toUpperCase();
            const symbol = type === "URL" ? "↗" : type === "PHONE_NUMBER" ? "📞" : "↩";
            return (
              <div
                key={idx}
                style={{
                  background: "#fff",
                  borderRadius: 6,
                  padding: "8px 10px",
                  fontSize: 13,
                  color: "#027eb5",
                  textAlign: "center",
                  fontWeight: 500,
                }}
              >
                {symbol} {b.text || "Button"}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

// AUTHENTICATION templates carry a Meta-managed "Copy code" button (type OTP,
// or returned on sync as a URL button pointing at whatsapp.com/otp/...). It is
// NOT a merchant-configurable link — WhatsApp auto-fills it with the OTP code
// at send time (see PreOrderOtpBspService). Treating it as a dynamic URL button
// wrongly forces a link-variable mapping and blocks "Save & turn on".
const isAuthTemplate = (template) =>
  (template?.category || "").toUpperCase() === "AUTHENTICATION";

// True if the template's BUTTONS component has a *merchant-configurable* URL
// button with a {{N}} placeholder — Meta then needs a value for it at send
// time, so the merchant must pick which link variable fills it. OTP/copy-code
// buttons on authentication templates are excluded: they're auto-filled.
const hasDynamicUrlButton = (template) => {
  if (isAuthTemplate(template)) return false;
  const bc = (template?.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "BUTTONS"
  );
  return (bc?.buttons || []).some((b) => {
    const type = (b?.type || "").toUpperCase();
    if (type === "OTP") return false; // Meta-managed OTP code button
    return type === "URL" && String(b.url || "").includes("{{");
  });
};

// The approved button's display label (fixed by Meta) — used to keep the
// persisted url_button.text consistent.
const urlButtonText = (template) => {
  const bc = (template?.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "BUTTONS"
  );
  const ub = (bc?.buttons || []).find((b) => (b?.type || "").toUpperCase() === "URL");
  return ub?.text || template?.urlButton?.text || "Open link";
};

const ConfirmMappingModal = ({ event, template, editing = false, onCancel, onConfirm }) => {
  const positions = useMemo(
    () => extractPositions(bodyTextOf(template)),
    [template]
  );
  const eventVars = event?.variables || [];
  const urlVars = eventVars.filter((v) => v.kind === "url");
  const showUrlButton = useMemo(() => hasDynamicUrlButton(template), [template]);

  // Header image (IMAGE-header templates). Default to the product image unless
  // the template already carries a fixed image, in which case keep that.
  const headerComp = useMemo(() => headerComponentOf(template), [template]);
  const isImageHeader = (headerComp?.format || "").toUpperCase() === "IMAGE";
  const headerMedia = template?.headerMedia || {};
  const hasFixedHeaderImage =
    !!headerMedia.mediaId ||
    !!headerMedia.media_id ||
    !!headerMedia.url ||
    (headerMedia.source === "url" && !!headerMedia.value);
  const [headerMode, setHeaderMode] = useState(
    hasFixedHeaderImage ? "fixed" : "product",
  );
  const [headerImageUrl, setHeaderImageUrl] = useState(
    headerMedia.url || (headerMedia.source === "url" ? headerMedia.value : "") || "",
  );
  const headerUrlValid = /^https?:\/\//i.test(headerImageUrl.trim());

  const [mapping, setMapping] = useState(() => {
    // Pre-fill with the template's current mapping, but only keep entries
    // whose variable still exists on this event. Anything stale stays blank
    // so the merchant has to make an active choice.
    const initial = {};
    const eventKeys = new Set(eventVars.map((v) => v.key));
    positions.forEach((p) => {
      const existing = template?.variableMapping?.[p];
      if (existing && eventKeys.has(existing)) initial[p] = existing;
    });
    return initial;
  });

  // The URL button's link variable (e.g. cart.recovery_url). Pre-fill from the
  // template's saved url_button, else default to the first URL variable.
  const [urlVariable, setUrlVariable] = useState(
    template?.urlButton?.variable || (showUrlButton ? urlVars[0]?.key || "" : "")
  );

  const headerOk =
    !isImageHeader ||
    headerMode === "product" ||
    (headerMode === "fixed" && headerUrlValid);

  const allMapped =
    positions.every((p) => mapping[p]) &&
    (!showUrlButton || !!urlVariable) &&
    headerOk;

  const handleConfirm = () => {
    const savedButton = template?.urlButton || {};
    const preservedFallback =
      savedButton.fallbackVariable || savedButton.fallback_variable;
    const urlButton =
      showUrlButton && urlVariable
        ? {
            mode: "predefined",
            variable: urlVariable,
            text: urlButtonText(template),
            ...(preservedFallback ? { fallback_variable: preservedFallback } : {}),
          }
        : null;
    let headerMediaPayload;
    if (isImageHeader) {
      headerMediaPayload =
        headerMode === "fixed"
          ? { mode: "fixed", source: "url", url: headerImageUrl.trim() }
          : { mode: "order_product_image" };
    }
    onConfirm({ variableMapping: mapping, urlButton, headerMedia: headerMediaPayload });
  };

  return (
    <Modal
      open
      onClose={onCancel}
      title={editing ? `Change variables — ${template?.name}` : `Confirm variables for "${template?.name}"`}
      primaryAction={{
        content: editing ? "Save" : "Save & turn on",
        onAction: handleConfirm,
        disabled: !allMapped,
      }}
      secondaryActions={[{ content: I18n.t("whatsapp_event_mappings.cancel"), onAction: onCancel }]}
    >
      <Modal.Section>
        <BlockStack gap="300">
          <Text as="p">
            {editing ? (
              <>
                {I18n.t("whatsapp_event_mappings.update_which")} <strong>{event?.label}</strong> {I18n.t("whatsapp_event_mappings.field_fills_each_placeholder_the_header")}
              </>
            ) : (
              <>
                {I18n.t("whatsapp_event_mappings.template_not_set_up_for_event", {
                  event: event?.label ?? "",
                  event_lower: event?.label?.toLowerCase() ?? "",
                })}
              </>
            )}
          </Text>
          {positions.length === 0 && !showUrlButton && !isImageHeader && (
            <Banner tone="info">
              {I18n.t("whatsapp_event_mappings.no_variables_in_this_template_s")}
            </Banner>
          )}
          {positions.map((p) => (
            <Select
              key={p}
              label={`{{${p}}}`}
              options={[
                { label: I18n.t("whatsapp_event_mappings.choose_a_variable"), value: "" },
                ...eventVars.map((v) => ({ label: v.label, value: v.key })),
              ]}
              value={mapping[p] || ""}
              onChange={(v) => setMapping((prev) => ({ ...prev, [p]: v }))}
            />
          ))}

          {isImageHeader && (
            <>
              <Divider />
              <Text as="h3" variant="headingSm">
                {I18n.t("whatsapp_event_mappings.header_image")}
              </Text>
              <Select
                label={I18n.t("whatsapp_event_mappings.what_image_should_this_notification_send")}
                options={[
                  { label: I18n.t("whatsapp_event_mappings.the_product_image_from_this_event"), value: "product" },
                  { label: I18n.t("whatsapp_event_mappings.a_fixed_image_same_every_time"), value: "fixed" },
                ]}
                value={headerMode}
                onChange={setHeaderMode}
              />
              {headerMode === "product" ? (
                <Banner tone="info">
                  {I18n.t("whatsapp_event_mappings.product_image_header_note", {
                    event: event?.label?.toLowerCase() ?? "",
                  })}
                </Banner>
              ) : (
                <TextField
                  label={I18n.t("whatsapp_event_mappings.image_url")}
                  value={headerImageUrl}
                  onChange={setHeaderImageUrl}
                  autoComplete="off"
                  placeholder="https://…/banner.jpg"
                  helpText={I18n.t("whatsapp_event_mappings.a_public_jpg_or_png_we")}
                  error={
                    headerImageUrl.trim() && !headerUrlValid
                      ? "Enter a full https:// image URL"
                      : undefined
                  }
                />
              )}
            </>
          )}

          {showUrlButton && (
            <>
              <Divider />
              <Text as="h3" variant="headingSm">
                {I18n.t("whatsapp_event_mappings.button_link")}
              </Text>
              <Text as="p" tone="subdued" variant="bodySm">
                {I18n.t("whatsapp_event_mappings.url_button_opens_dynamic_link", {
                  button: urlButtonText(template),
                })}
              </Text>
              {urlVars.length === 0 ? (
                <Banner tone="warning">
                  {I18n.t("whatsapp_event_mappings.this_event_has_no_link_variable")}
                </Banner>
              ) : (
                <Select
                  label={I18n.t("whatsapp_event_mappings.open_this_link")}
                  options={[
                    { label: I18n.t("whatsapp_event_mappings.choose_a_link"), value: "" },
                    ...urlVars.map((v) => ({ label: v.label, value: v.key })),
                  ]}
                  value={urlVariable}
                  onChange={setUrlVariable}
                />
              )}
            </>
          )}

          <Divider />
          <Text as="h3" variant="headingSm">
            {I18n.t("whatsapp_event_mappings.preview")}
          </Text>
          <Text as="p" tone="subdued" variant="bodySm">
            {I18n.t("whatsapp_event_mappings.how_the_message_looks_with_sample")}
          </Text>
          <MappingPreview template={template} event={event} mapping={mapping} />
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

const COD_VERIFICATION_EVENT_KEY = "cod_verification";

export const NotificationPauseButton = ({ eventKey, paused, variant, disabled, onChanged, onError }) => {
  const [confirming, setConfirming] = useState(false);
  const [{ loading }, postPause] = useApi(
    { url: "/api/whatsapp/template_bindings/pause", method: "POST" },
    { manual: true }
  );

  const submit = async (nextPaused) => {
    setConfirming(false);
    try {
      const res = await postPause({ data: { event_type_key: eventKey, paused: nextPaused } });
      onChanged?.(res?.data?.bindings || []);
    } catch (err) {
      onError?.(
        err?.response?.data?.error ||
          I18n.t("whatsapp_event_mappings.pause_failed", {
            defaultValue: "Couldn't update this notification. Try again.",
          })
      );
    }
  };

  const handleClick = () => {
    if (!paused && eventKey === COD_VERIFICATION_EVENT_KEY) {
      setConfirming(true);
    } else {
      submit(!paused);
    }
  };

  return (
    <>
      <Button variant={variant} loading={loading} disabled={disabled} onClick={handleClick}>
        {paused
          ? I18n.t("whatsapp_event_mappings.pause_resume", { defaultValue: "Resume" })
          : I18n.t("whatsapp_event_mappings.pause_pause", { defaultValue: "Pause" })}
      </Button>
      {confirming && (
        <Modal
          open
          onClose={() => setConfirming(false)}
          title={I18n.t("whatsapp_event_mappings.pause_cod_title", {
            defaultValue: "Pause COD verification?",
          })}
          primaryAction={{
            content: I18n.t("whatsapp_event_mappings.pause_cod_confirm", {
              defaultValue: "Pause verification",
            }),
            destructive: true,
            onAction: () => submit(true),
          }}
          secondaryActions={[
            {
              content: I18n.t("whatsapp_event_mappings.pause_cancel", { defaultValue: "Cancel" }),
              onAction: () => setConfirming(false),
            },
          ]}
        >
          <Modal.Section>
            <Text as="p">
              {I18n.t("whatsapp_event_mappings.pause_cod_warning", {
                defaultValue: "Orders won't be verified on WhatsApp while paused.",
              })}
            </Text>
          </Modal.Section>
        </Modal>
      )}
    </>
  );
};

// Events that surface a "send after N minutes" offset input on the regular
// single-stage BindingRow. cod_verification is the canonical one — merchants
// often want a buffer between order placement and the verification message.
// Events whose BSP send is dispatched through DispatchEventJob and therefore
// honour a per-notification delay (binding.offset_minutes). abandoned_cart is
// excluded — it has its own per-stage timing in the staged editor; OTP and
// cod_to_prepaid run through separate services with their own scheduling.
const OFFSET_AWARE_EVENTS = new Set([
  "order_created",
  "order_fulfilled",
  "first_time_purchase",
  "cod_verification",
  "cod_verification_reminder",
  "order_cancelled",
  "order_out_for_delivery",
  "order_delivered",
  "feedback_request",
  "reorder_reminder",
]);

const formatDelay = (minutes) => {
  if (minutes >= 1440 && minutes % 1440 === 0) return `${minutes / 1440} day${minutes === 1440 ? "" : "s"}`;
  if (minutes >= 60 && minutes % 60 === 0) return `${minutes / 60} hour${minutes === 60 ? "" : "s"}`;
  return `${minutes} min`;
};

const BindingRow = ({ event, approved, binding, onBind, onUnbind, onTest, onEditVariables, gated, onUpgrade }) => {
  const [pendingTemplateId, setPendingTemplateId] = useState(
    binding ? String(binding.whatsappTemplateId) : ""
  );
  const [pendingOffset, setPendingOffset] = useState(
    binding ? String(binding.offsetMinutes ?? 0) : "0"
  );
  // Delay popup state.
  const [delayOpen, setDelayOpen] = useState(false);
  const [delayDraft, setDelayDraft] = useState("0");
  const [savingDelay, setSavingDelay] = useState(false);

  useEffect(() => {
    setPendingTemplateId(binding ? String(binding.whatsappTemplateId) : "");
    setPendingOffset(binding ? String(binding.offsetMinutes ?? 0) : "0");
  }, [binding]);

  // When the shop has templates on more than one number, tag each option with
  // its number so picking a template also chooses which number the event sends
  // from (the binding follows the template's number).
  const multiNumber = new Set(approved.map((t) => t.whatsappAccountId)).size > 1;
  const numberSuffix = (t) => {
    const n = t.accountLabel || t.accountPhone;
    return multiNumber && n ? ` · ${n}` : "";
  };
  const options = [
    { label: approved.length ? "Pick a template…" : "No templates ready yet", value: "" },
    ...approved.map((t) => ({ label: `${t.name} (${t.language})${numberSuffix(t)}`, value: String(t.id) })),
  ];
  const boundNumber = binding?.accountLabel || binding?.accountPhone;

  const showsOffset = event && OFFSET_AWARE_EVENTS.has(event.key);
  const dirty =
    pendingTemplateId &&
    (!binding ||
      String(binding.whatsappTemplateId) !== pendingTemplateId ||
      (showsOffset && String(binding.offsetMinutes ?? 0) !== pendingOffset));

  return (
    <BlockStack gap="200">
      <InlineStack gap="200" blockAlign="end" wrap>
        <Box minWidth="280px">
          <Select
            label={I18n.t("whatsapp_event_mappings.send_this_template")}
            options={options}
            value={pendingTemplateId}
            onChange={setPendingTemplateId}
            disabled={gated}
            helpText={
              multiNumber
                ? "Picking a template assigns it to this trigger and sends from that template's number."
                : "Any approved template of a matching category can be used here — picking one assigns it to this trigger."
            }
          />
          {boundNumber && (
            <Box paddingBlockStart="100">
              <Text as="span" tone="subdued" variant="bodySm">
                {I18n.t("whatsapp_event_mappings.sends_from", {
                  number: boundNumber,
                })}
              </Text>
            </Box>
          )}
        </Box>
        {showsOffset && (
          <Box paddingBlockEnd="100">
            <Button
              variant="plain"
              disabled={gated}
              onClick={() => {
                setDelayDraft(pendingOffset || "0");
                setDelayOpen(true);
              }}
            >
              {Number(pendingOffset) > 0
                ? `Delay: ${formatDelay(Number(pendingOffset))} · Edit`
                : event?.defaultOffsetMinutes
                  ? `Delay: ${formatDelay(event.defaultOffsetMinutes)} (default) · Edit`
                  : "Set delay"}
            </Button>
          </Box>
        )}
        {gated ? (
          <Button variant="primary" onClick={onUpgrade}>
            {I18n.t("whatsapp_event_mappings.upgrade_to_turn_on")}
          </Button>
        ) : (
          <Button
            variant="primary"
            disabled={!dirty}
            onClick={async () => {
              // handleBind rethrows so the staged editor can show inline errors;
              // here the page-level banner already covers it, so just swallow.
              try {
                await onBind(Number(pendingTemplateId), showsOffset ? Number(pendingOffset) || 0 : 0);
              } catch (_) {
                /* surfaced via page banner */
              }
            }}
          >
            {binding ? "Change template" : "Turn on"}
          </Button>
        )}
        {binding && (
          <>
            <Button variant="plain" onClick={onEditVariables}>
              {I18n.t("whatsapp_event_mappings.change_variables")}
            </Button>
            <Button variant="plain" onClick={onTest}>
              {I18n.t("whatsapp_event_mappings.test")}
            </Button>
            <Button tone="critical" variant="plain" onClick={onUnbind}>
              {I18n.t("whatsapp_event_mappings.turn_off")}
            </Button>
          </>
        )}
      </InlineStack>
      {/* Shortcut to the library tab so merchants without an approved template
          for this event can grab a pre-made one without leaving the flow. */}
      <Text as="p" tone="subdued" variant="bodySm">
        {I18n.t("whatsapp_event_mappings.dont_see_the_right_one")}{" "}
        <a
          href="#"
          onClick={(e) => {
            e.preventDefault();
            window.dispatchEvent(
              new CustomEvent("whatsapp:goto-tab", { detail: "library" })
            );
          }}
        >
          {I18n.t("whatsapp_event_mappings.browse_pre_made_templates")}
        </a>
        {" "}
        {I18n.t("whatsapp_event_mappings.or")}{" "}
        <a
          href="#"
          onClick={(e) => {
            e.preventDefault();
            window.dispatchEvent(
              new CustomEvent("whatsapp:goto-tab", { detail: "create" })
            );
          }}
        >
          {I18n.t("whatsapp_event_mappings.write_your_own")}
        </a>
        .
      </Text>

      <Modal
        open={delayOpen}
        onClose={() => setDelayOpen(false)}
        title={I18n.t("whatsapp_event_mappings.set_delay")}
        primaryAction={{
          content: I18n.t("whatsapp_event_mappings.save"),
          loading: savingDelay,
          onAction: async () => {
            const val = Math.max(0, Number(delayDraft) || 0);
            setPendingOffset(String(val));
            // Persist immediately when the notification is already on; otherwise
            // the value is applied when the merchant turns it on.
            if (binding && pendingTemplateId) {
              setSavingDelay(true);
              try {
                await onBind(Number(pendingTemplateId), val);
              } catch (_) {
                /* surfaced via page banner */
              } finally {
                setSavingDelay(false);
              }
            }
            setDelayOpen(false);
          },
        }}
        secondaryActions={[{ content: I18n.t("whatsapp_event_mappings.cancel"), onAction: () => setDelayOpen(false) }]}
      >
        <Modal.Section>
          <BlockStack gap="200">
            <TextField
              type="number"
              label={I18n.t("whatsapp_event_mappings.send_after_minutes")}
              value={delayDraft}
              onChange={setDelayDraft}
              min={0}
              autoComplete="off"
              helpText={I18n.t("whatsapp_event_mappings.0_send_immediately_when_the_event")}
            />
          </BlockStack>
        </Modal.Section>
      </Modal>
    </BlockStack>
  );
};

// Multi-stage editor for any event in STAGED_EVENT_KEYS.
const AbandonedCartStagesEditor = ({
  approved,
  stages,
  onSaveStage,
  onRemoveStage,
  onTest,
  gated,
  onUpgrade,
}) => {
  // A draft row is a fresh stage the merchant is configuring before it has
  // hit the API. After save it disappears (since `stages` will then include it).
  const [drafts, setDrafts] = useState([]);

  const usedStageIndexes = new Set(stages.map((s) => s.stageIndex || 0));
  const nextStageIndex = (() => {
    let i = 0;
    while (usedStageIndexes.has(i) || drafts.some((d) => d.stageIndex === i)) i += 1;
    return i;
  })();

  // Default offsets for a fresh stage — gentle escalation that matches the
  // pre-made library entries (30 min → 24h → 72h → 7d for further).
  const defaultOffsetForStage = (i) => [30, 60 * 24, 60 * 72, 60 * 24 * 7][i] || 60 * 24;

  const addDraft = () => {
    setDrafts((prev) => [
      ...prev,
      {
        stageIndex: nextStageIndex,
        whatsappTemplateId: "",
        offsetMinutes: defaultOffsetForStage(nextStageIndex),
        discountConfig: { mode: "none" },
      },
    ]);
  };

  const removeDraft = (stageIndex) =>
    setDrafts((prev) => prev.filter((d) => d.stageIndex !== stageIndex));

  return (
    <BlockStack gap="300">
      <Text as="p" tone="subdued" variant="bodySm">
        {I18n.t("whatsapp_event_mappings.each_reminder_is_sent_n_minutes")}
      </Text>

      {stages.map((stage) => (
        <StageEditorRow
          key={stage.id}
          stageIndex={stage.stageIndex || 0}
          approved={approved}
          initialTemplateId={stage.whatsappTemplateId}
          initialOffsetMinutes={stage.offsetMinutes ?? 0}
          initialDiscount={stage.discountConfig || { mode: "none" }}
          gated={gated}
          onUpgrade={onUpgrade}
          onSave={(form) =>
            onSaveStage({
              stageIndex: stage.stageIndex || 0,
              ...form,
            })
          }
          onRemove={() => onRemoveStage(stage.id)}
          onTest={() => onTest(stage)}
        />
      ))}

      {drafts.map((draft) => (
        <StageEditorRow
          key={`draft-${draft.stageIndex}`}
          stageIndex={draft.stageIndex}
          approved={approved}
          initialTemplateId={draft.whatsappTemplateId}
          initialOffsetMinutes={draft.offsetMinutes}
          initialDiscount={draft.discountConfig}
          isDraft
          gated={gated}
          onUpgrade={onUpgrade}
          onSave={(form) =>
            onSaveStage({
              stageIndex: draft.stageIndex,
              ...form,
            }).then(() => removeDraft(draft.stageIndex))
          }
          onRemove={() => removeDraft(draft.stageIndex)}
        />
      ))}

      <InlineStack gap="200">
        {gated ? (
          <Button variant="primary" onClick={onUpgrade}>{I18n.t("whatsapp_event_mappings.upgrade_to_turn_on")}</Button>
        ) : (
          <Button onClick={addDraft}>{I18n.t("whatsapp_event_mappings.add_reminder")}</Button>
        )}
      </InlineStack>
    </BlockStack>
  );
};

const DISCOUNT_MODES = [
  { get label() {
      return I18n.t("whatsapp_event_mappings.no_discount");
    }, value: "none" },
  { get label() {
      return I18n.t("whatsapp_event_mappings.static_code_e_g_welcome10");
    }, value: "static" },
  { get label() {
      return I18n.t("whatsapp_event_mappings.auto_generated_shopify_code_one_per");
    }, value: "auto" },
];

const DISCOUNT_KINDS = [
  { get label() {
      return I18n.t("whatsapp_event_mappings.percent_off");
    }, value: "percent" },
  { get label() {
      return I18n.t("whatsapp_event_mappings.fixed_amount_off");
    }, value: "fixed" },
];

const StageEditorRow = ({
  stageIndex,
  approved,
  initialTemplateId,
  initialOffsetMinutes,
  initialDiscount,
  isDraft = false,
  gated = false,
  onUpgrade,
  onSave,
  onRemove,
  onTest,
}) => {
  const [templateId, setTemplateId] = useState(
    initialTemplateId ? String(initialTemplateId) : ""
  );
  const [offsetMinutes, setOffsetMinutes] = useState(String(initialOffsetMinutes ?? 0));
  const [discount, setDiscount] = useState(initialDiscount || { mode: "none" });
  const [saving, setSaving] = useState(false);

  const setDiscountField = (k, v) =>
    setDiscount((prev) => ({ ...prev, [k]: v }));

  const multiNumber = new Set(approved.map((t) => t.whatsappAccountId)).size > 1;
  const templateOptions = [
    { label: I18n.t("whatsapp_event_mappings.pick_a_template"), value: "" },
    ...approved.map((t) => {
      const n = t.accountLabel || t.accountPhone;
      const suffix = multiNumber && n ? ` · ${n}` : "";
      return { label: `${t.name} (${t.language})${suffix}`, value: String(t.id) };
    }),
  ];

  const selectedTemplate = approved.find((t) => String(t.id) === templateId);
  // Does the chosen template already map a {{N}} to a discount.* variable?
  const templateMapsDiscount = Object.values(
    selectedTemplate?.variableMapping || {}
  ).some((v) => String(v).startsWith("discount."));
  // How many {{N}} placeholders the body has — i.e. whether there's any slot a
  // discount could ever be shown in.
  const templatePlaceholderCount = selectedTemplate
    ? extractPositions(bodyTextOf(selectedTemplate)).length
    : 0;
  const discountConfigured = (discount.mode || "none") !== "none";

  // Hard block: a discount is set but the template body has NO placeholder at
  // all, so the code can never be shown. Pick a template with a placeholder.
  const discountImpossible =
    discountConfigured && !!templateId && templatePlaceholderCount === 0;
  // Soft note: the template has placeholders but the discount isn't mapped to
  // one yet. That's fine — turning it on opens the variable picker where the
  // discount gets mapped, so we don't block here.
  const discountNeedsMapping =
    discountConfigured && !!templateId && templatePlaceholderCount > 0 && !templateMapsDiscount;
  // Template maps a discount but none is configured — it'll render as "—".
  const discountExpectedButNone =
    !discountConfigured && !!templateId && templateMapsDiscount;

  const [saveError, setSaveError] = useState("");

  const handleSave = async () => {
    if (!templateId || discountImpossible) return;
    setSaving(true);
    setSaveError("");
    try {
      await onSave({
        whatsappTemplateId: Number(templateId),
        offsetMinutes: Number(offsetMinutes) || 0,
        discountConfig: discount,
      });
    } catch (err) {
      setSaveError(err?.message || "Couldn't save this reminder.");
    } finally {
      setSaving(false);
    }
  };

  const headerLabel = `Reminder ${stageIndex + 1}${isDraft ? " (draft)" : ""}`;

  return (
    <Box
      padding="300"
      borderColor="border"
      borderWidth="025"
      borderRadius="200"
      background="bg-surface-secondary"
    >
      <BlockStack gap="200">
        <InlineStack align="space-between" blockAlign="center">
          <Text as="h4" variant="headingSm">
            {headerLabel}
          </Text>
          <Button variant="plain" tone="critical" onClick={onRemove}>
            {I18n.t("whatsapp_event_mappings.remove")}
          </Button>
        </InlineStack>

        <InlineStack gap="200" blockAlign="end" wrap>
          <Box minWidth="260px">
            <Select
              label={I18n.t("whatsapp_event_mappings.template")}
              options={templateOptions}
              value={templateId}
              onChange={setTemplateId}
              disabled={gated}
            />
          </Box>
          <Box minWidth="180px">
            <TextField
              type="number"
              label={I18n.t("whatsapp_event_mappings.send_after_minutes")}
              value={offsetMinutes}
              onChange={setOffsetMinutes}
              min={0}
              autoComplete="off"
              helpText={
                Number(offsetMinutes) >= 60
                  ? `${(Number(offsetMinutes) / 60).toFixed(1)} hours`
                  : undefined
              }
            />
          </Box>
        </InlineStack>

        <InlineStack gap="200" blockAlign="end" wrap>
          <Box minWidth="220px">
            <Select
              label={I18n.t("whatsapp_event_mappings.discount")}
              options={DISCOUNT_MODES}
              value={discount.mode || "none"}
              onChange={(v) =>
                // Seed kind so it matches the "Percent off" default shown in the
                // Kind select — otherwise it's never written to state and the
                // binding posts without a kind.
                setDiscount(v === "none" ? { mode: v } : { mode: v, kind: "percent" })
              }
            />
          </Box>
          {discount.mode === "static" && (
            <>
              <Box minWidth="160px">
                <TextField
                  label={I18n.t("whatsapp_event_mappings.code")}
                  value={discount.code || ""}
                  onChange={(v) => setDiscountField("code", v)}
                  autoComplete="off"
                />
              </Box>
              <Box minWidth="120px">
                <Select
                  label={I18n.t("whatsapp_event_mappings.kind")}
                  options={DISCOUNT_KINDS}
                  value={discount.kind || "percent"}
                  onChange={(v) => setDiscountField("kind", v)}
                />
              </Box>
              <Box minWidth="100px">
                <TextField
                  type="number"
                  label={I18n.t("whatsapp_event_mappings.value")}
                  value={String(discount.value ?? "")}
                  onChange={(v) => setDiscountField("value", Number(v))}
                  min={0}
                  autoComplete="off"
                />
              </Box>
            </>
          )}
          {discount.mode === "auto" && (
            <>
              <Box minWidth="120px">
                <Select
                  label={I18n.t("whatsapp_event_mappings.kind")}
                  options={DISCOUNT_KINDS}
                  value={discount.kind || "percent"}
                  onChange={(v) => setDiscountField("kind", v)}
                />
              </Box>
              <Box minWidth="100px">
                <TextField
                  type="number"
                  label={I18n.t("whatsapp_event_mappings.value")}
                  value={String(discount.value ?? "")}
                  onChange={(v) => setDiscountField("value", Number(v))}
                  min={0}
                  autoComplete="off"
                />
              </Box>
              <Box minWidth="100px">
                <TextField
                  type="number"
                  label={I18n.t("whatsapp_event_mappings.cap_upto")}
                  value={String(discount.upto ?? "")}
                  onChange={(v) => setDiscountField("upto", Number(v))}
                  min={0}
                  autoComplete="off"
                  helpText={I18n.t("whatsapp_event_mappings.caps_percent_off_to_this_max")}
                />
              </Box>
              <Box minWidth="100px">
                <TextField
                  label={I18n.t("whatsapp_event_mappings.prefix")}
                  value={discount.prefix || "AC"}
                  onChange={(v) => setDiscountField("prefix", v)}
                  autoComplete="off"
                  helpText={I18n.t("whatsapp_event_mappings.code_starts_with_this")}
                />
              </Box>
            </>
          )}
        </InlineStack>

        {discountImpossible && (
          <Banner tone="critical">
            {I18n.t("whatsapp_event_mappings.no_placeholder_for_discount", {
              none: I18n.t("whatsapp_event_mappings.none"),
            })}
          </Banner>
        )}
        {discountNeedsMapping && (
          <Banner tone="info">
            {I18n.t("whatsapp_event_mappings.pick_which_placeholder_shows_code")}
          </Banner>
        )}
        {discountExpectedButNone && (
          <Banner tone="warning">
            {I18n.t("whatsapp_event_mappings.discount_variable_unconfigured")}
          </Banner>
        )}
        {saveError && (
          <Banner tone="critical" onDismiss={() => setSaveError("")}>
            {saveError}
          </Banner>
        )}

        <InlineStack gap="200">
          {gated ? (
            <Button variant="primary" onClick={onUpgrade}>
              {I18n.t("whatsapp_event_mappings.upgrade_to_turn_on")}
            </Button>
          ) : (
            <Button
              variant="primary"
              onClick={handleSave}
              disabled={!templateId || saving || discountImpossible}
              loading={saving}
            >
              {isDraft ? "Add reminder" : "Save changes"}
            </Button>
          )}
          {!isDraft && onTest && (
            <Button variant="plain" onClick={onTest}>
              {`Test reminder ${stageIndex + 1}`}
            </Button>
          )}
        </InlineStack>
      </BlockStack>
    </Box>
  );
};

const DELAY_UNITS = [
  { label: "minutes", value: "minutes" },
  { label: "hours", value: "hours" },
  { label: "days", value: "days" },
];

const PREPAID_DISCOUNT_TYPES = [
  { label: "Fixed amount", value: "FIXED" },
  { label: "Percentage", value: "PERCENTAGE" },
];

const minutesToDelay = (mins) => {
  const n = Number(mins) || 0;
  if (!n) return { value: 30, unit: "minutes" };
  if (n % 1440 === 0) return { value: n / 1440, unit: "days" };
  if (n % 60 === 0) return { value: n / 60, unit: "hours" };
  return { value: n, unit: "minutes" };
};

const delayToMinutes = (value, unit) => {
  const n = Number(value) || 0;
  if (unit === "days") return n * 1440;
  if (unit === "hours") return n * 60;
  return n;
};

const reminderUuid = () => {
  // CSPRNG-backed v4; also removes the `| 0` truncation the linter flags.
  const rng =
    typeof globalThis !== "undefined" && globalThis.crypto ? globalThis.crypto : null;
  if (rng && typeof rng.randomUUID === "function") return rng.randomUUID();
  if (rng && typeof rng.getRandomValues === "function") {
    const bytes = new Uint8Array(16);
    rng.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0"));
    return `${hex.slice(0,4).join("")}-${hex.slice(4,6).join("")}-${hex.slice(6,8).join("")}-${hex.slice(8,10).join("")}-${hex.slice(10,16).join("")}`;
  }
  throw new Error("Secure random source unavailable; cannot generate id");
};

// The jsonb column can come back double-encoded as a JSON string (e.g. "[]"),
// which would otherwise leave the card spinning forever.
const asReminderArray = (val) => {
  if (Array.isArray(val)) return val;
  if (typeof val === "string") {
    try {
      const parsed = JSON.parse(val);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
};

const describeReminder = (r, approved, defaultTemplateName) => {
  const dly = minutesToDelay(r.delayMinutes);
  const range =
    r.cartMin == null && r.cartMax == null
      ? "all carts"
      : r.cartMin != null && r.cartMax != null
      ? `carts ${r.cartMin}–${r.cartMax}`
      : r.cartMin != null
      ? `carts ${r.cartMin}+`
      : `carts under ${r.cartMax}`;
  const discount =
    r.discount == null
      ? "default discount"
      : `${r.discount}${r.discountType === "PERCENTAGE" ? "%" : ""} off`;
  const tpl = approved.find((t) => String(t.id) === String(r.bspTemplateId));
  const tplLabel = tpl
    ? tpl.name
    : defaultTemplateName
    ? `${defaultTemplateName} (default)`
    : "default template";
  return `${dly.value} ${dly.unit} after the order · ${range} · ${discount} · ${tplLabel}`;
};

const PrepaidReminderRow = ({
  reminder,
  index,
  approved,
  gated,
  defaultTemplateName,
  onChange,
  onRemove,
}) => {
  const dly = minutesToDelay(reminder.delayMinutes);
  const set = (patch) => onChange({ ...reminder, ...patch });
  const setDelay = (value, unit) =>
    set({ delayMinutes: delayToMinutes(value, unit) });

  const multiNumber = new Set(approved.map((t) => t.whatsappAccountId)).size > 1;
  const templateOptions = [
    {
      label: defaultTemplateName
        ? `Default for this trigger (${defaultTemplateName})`
        : "Default for this trigger",
      value: "",
    },
    ...approved.map((t) => {
      const n = t.accountLabel || t.accountPhone;
      const suffix = multiNumber && n ? ` · ${n}` : "";
      return { label: `${t.name} (${t.language})${suffix}`, value: String(t.id) };
    }),
  ];

  const useDiscount = reminder.discount != null;

  return (
    <Box
      padding="300"
      borderColor="border"
      borderWidth="025"
      borderRadius="200"
      background="bg-surface-secondary"
    >
      <BlockStack gap="200">
        <InlineStack align="space-between" blockAlign="center">
          <InlineStack gap="200" blockAlign="center">
            <Text as="h4" variant="headingSm">
              {reminder.label || `Reminder ${index + 1}`}
            </Text>
            {reminder.enabled === false && <Badge tone="critical">Off</Badge>}
          </InlineStack>
          <Button variant="plain" tone="critical" onClick={onRemove} disabled={gated}>
            Remove
          </Button>
        </InlineStack>

        <Text as="p" tone="subdued" variant="bodySm">
          {describeReminder(reminder, approved, defaultTemplateName)}
        </Text>

        <InlineStack gap="200" blockAlign="end" wrap>
          <Box minWidth="140px">
            <TextField
              label="Send after"
              type="number"
              min={1}
              value={String(dly.value)}
              onChange={(v) => setDelay(v, dly.unit)}
              autoComplete="off"
              disabled={gated}
            />
          </Box>
          <Box minWidth="140px">
            <Select
              label="Unit"
              options={DELAY_UNITS}
              value={dly.unit}
              onChange={(v) => setDelay(dly.value, v)}
              disabled={gated}
            />
          </Box>
          <Box minWidth="200px">
            <TextField
              label="Label (optional)"
              value={reminder.label || ""}
              onChange={(v) => set({ label: v })}
              autoComplete="off"
              disabled={gated}
            />
          </Box>
        </InlineStack>

        <InlineStack gap="200" blockAlign="end" wrap>
          <Box minWidth="160px">
            <TextField
              label="Cart min"
              type="number"
              min={0}
              value={reminder.cartMin == null ? "" : String(reminder.cartMin)}
              onChange={(v) => set({ cartMin: v === "" ? null : Number(v) })}
              autoComplete="off"
              disabled={gated}
              helpText="Blank = no floor"
            />
          </Box>
          <Box minWidth="160px">
            <TextField
              label="Cart max"
              type="number"
              min={0}
              value={reminder.cartMax == null ? "" : String(reminder.cartMax)}
              onChange={(v) => set({ cartMax: v === "" ? null : Number(v) })}
              autoComplete="off"
              disabled={gated}
              helpText="Blank = no cap"
            />
          </Box>
          <Box minWidth="280px">
            <Select
              label="Send this template"
              options={templateOptions}
              value={reminder.bspTemplateId ? String(reminder.bspTemplateId) : ""}
              onChange={(v) => set({ bspTemplateId: v ? Number(v) : null })}
              disabled={gated}
            />
          </Box>
        </InlineStack>

        <Checkbox
          label="Override the shop's prepaid discount"
          checked={useDiscount}
          disabled={gated}
          onChange={(v) =>
            set(
              v
                ? { discount: 0, discountType: reminder.discountType || "FIXED" }
                : { discount: null, discountType: null }
            )
          }
        />
        {useDiscount && (
          <InlineStack gap="200" blockAlign="end" wrap>
            <Box minWidth="160px">
              <TextField
                label="Discount"
                type="number"
                min={0}
                value={String(reminder.discount ?? "")}
                onChange={(v) => set({ discount: v === "" ? 0 : Number(v) })}
                autoComplete="off"
                disabled={gated}
              />
            </Box>
            <Box minWidth="180px">
              <Select
                label="Type"
                options={PREPAID_DISCOUNT_TYPES}
                value={reminder.discountType || "FIXED"}
                onChange={(v) => set({ discountType: v })}
                disabled={gated}
              />
            </Box>
          </InlineStack>
        )}

        <Checkbox
          label="Also waive shipping"
          helpText="The order's Shopify shipping charge is added on top of the discount."
          checked={reminder.addShipping === true}
          onChange={(v) => set({ addShipping: v })}
          disabled={gated}
        />
        <Checkbox
          label="Enabled"
          checked={reminder.enabled !== false}
          onChange={(v) => set({ enabled: v })}
          disabled={gated}
        />
      </BlockStack>
    </Box>
  );
};

const PrepaidRemindersEditor = ({ approved, gated, onUpgrade, defaultTemplateName }) => {
  const [{ data, error }] = useApi(
    { url: "/api/prepaid_reminders", method: "GET" },
    { manual: false }
  );
  const [, saveApi] = useApi(
    { url: "/api/prepaid_reminders", method: "PATCH" },
    { manual: true }
  );

  const [working, setWorking] = useState(null);
  // Baseline needs its own state rather than being read off the GET response:
  // the PATCH reply is newer than the cached GET, so comparing against the GET
  // would leave the card permanently dirty after a save.
  const [baseline, setBaseline] = useState(null);
  const [saveState, setSaveState] = useState({ saving: false, error: "", success: "" });

  useEffect(() => {
    if (working != null) return;
    const seed = data ? asReminderArray(data.reminders) : error ? [] : null;
    if (seed == null) return;
    setWorking(seed);
    setBaseline(seed);
  }, [data, error, working]);

  const reminders = working || [];
  const dirty = useMemo(
    () => JSON.stringify(reminders) !== JSON.stringify(baseline || []),
    [reminders, baseline]
  );

  if (error?.response?.status === 404) return null;

  if (working == null) {
    return (
      <InlineStack gap="200" blockAlign="center">
        <Spinner size="small" />
        <Text as="span" tone="subdued" variant="bodySm">
          Loading reminders…
        </Text>
      </InlineStack>
    );
  }

  const addReminder = () =>
    setWorking((prev) => [
      ...(prev || []),
      {
        id: reminderUuid(),
        enabled: true,
        label: "",
        delayMinutes: [30, 60 * 24, 60 * 72][(prev || []).length] || 60 * 24,
        cartMin: null,
        cartMax: null,
        discount: null,
        discountType: null,
        addShipping: false,
        bspTemplateId: null,
      },
    ]);

  const updateReminder = (updated) =>
    setWorking((prev) => (prev || []).map((r) => (r.id === updated.id ? updated : r)));

  const removeReminder = (id) =>
    setWorking((prev) => (prev || []).filter((r) => r.id !== id));

  const persist = async () => {
    setSaveState({ saving: true, error: "", success: "" });
    try {
      const { data: saved } = await saveApi({ data: { reminders } });
      const confirmed = asReminderArray(saved.reminders);
      setWorking(confirmed);
      setBaseline(confirmed);
      setSaveState({ saving: false, error: "", success: "Reminders saved" });
      setTimeout(() => setSaveState((s) => ({ ...s, success: "" })), 2000);
    } catch (err) {
      setSaveState({
        saving: false,
        error: err?.response?.data?.error || err?.message || "Couldn't save reminders",
        success: "",
      });
    }
  };

  return (
    <BlockStack gap="300">
      <InlineStack align="space-between" blockAlign="center" wrap>
        <BlockStack gap="050">
          <InlineStack gap="200" blockAlign="center">
            <Text as="h4" variant="headingSm">
              Reminders
            </Text>
            {reminders.length > 0 && (
              <Badge tone="success">
                {`${reminders.length} reminder${reminders.length === 1 ? "" : "s"}`}
              </Badge>
            )}
          </InlineStack>
          <Text as="p" tone="subdued" variant="bodySm">
            Every new COD order fires each reminder whose cart range matches, at its own
            delay. These are the same reminders as the ones on the Prepaid settings page —
            editing them here changes them everywhere.
          </Text>
        </BlockStack>
        {gated ? (
          <Button variant="primary" onClick={onUpgrade}>
            Upgrade to turn on
          </Button>
        ) : (
          <Button onClick={addReminder}>+ Add reminder</Button>
        )}
      </InlineStack>

      {saveState.error && (
        <Banner tone="critical" onDismiss={() => setSaveState((s) => ({ ...s, error: "" }))}>
          {saveState.error}
        </Banner>
      )}
      {saveState.success && <Banner tone="success">{saveState.success}</Banner>}

      {reminders.length === 0 ? (
        <Banner tone="info">
          No reminders yet — the trigger sends once on the schedule set in Prepaid settings.
          Add a reminder to send several nudges with their own delay, cart range, discount
          and template.
        </Banner>
      ) : (
        reminders.map((r, i) => (
          <PrepaidReminderRow
            key={r.id}
            reminder={r}
            index={i}
            approved={approved}
            gated={gated}
            defaultTemplateName={defaultTemplateName}
            onChange={updateReminder}
            onRemove={() => removeReminder(r.id)}
          />
        ))
      )}

      {dirty && !gated && (
        <InlineStack align="end" gap="200">
          <Button onClick={() => setWorking(baseline || [])}>Discard changes</Button>
          <Button variant="primary" loading={saveState.saving} onClick={persist}>
            Save reminders
          </Button>
        </InlineStack>
      )}
    </BlockStack>
  );
};

export default WhatsappEventMappings;

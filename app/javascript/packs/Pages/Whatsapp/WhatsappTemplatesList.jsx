import React, {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import ReactDOM from "react-dom";
import {
  Card,
  BlockStack,
  InlineStack,
  Box,
  Text,
  Button,
  Badge,
  Spinner,
  Banner,
  EmptyState,
  Modal,
  Select,
  TextField,
  Divider,
  Tabs,
} from "@shopify/polaris";
import { RefreshMinor } from "@shopify/polaris-icons";
import useApi from "../../Hooks/useApi";
import Api from "../../Services/Api";

import I18n from "../../i18n-lang";
// Human-readable label per raw template status. Falls back to the original
// label if we hit an unknown state — better to surface "PAUSED" than nothing.
const statusLabel = (status) => {
  switch ((status || "").toUpperCase()) {
    case "APPROVED":           return "Approved";
    case "PENDING":            return "Waiting for WhatsApp approval";
    case "IN_APPEAL":          return "Appeal in progress";
    case "PENDING_DELETION":   return "Deleting…";
    case "REJECTED":           return "Rejected by WhatsApp";
    case "DISABLED":           return "Disabled by WhatsApp";
    case "PAUSED":             return "Paused by WhatsApp";
    case "FAILED":             return "Failed";
    default:                   return status || "Unknown";
  }
};

const statusTone = (status) => {
  switch ((status || "").toUpperCase()) {
    case "APPROVED":
      return "success";
    case "PENDING":
    case "IN_APPEAL":
    case "PENDING_DELETION":
      return "attention";
    case "REJECTED":
    case "DISABLED":
    case "PAUSED":
    case "FAILED":
      return "critical";
    default:
      return "info";
  }
};

const escapeHtml = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// Resolve a template's body/header text by replacing {{N}} with a friendly
// label of the mapped event variable (e.g. `{customer first name}`). Falls
// back to the variable's sample value, then to `{value_N}` for un-mapped slots.
//
// We render the friendly label instead of just the sample so merchants see
// what FIELD is going to be sent — not just one example value. This is a key
// part of the "{{1}} is too technical" rework.
const fillSamples = (text, variableMapping, eventVarSamples, eventVarLabels) => {
  if (!text) return "";
  return escapeHtml(text)
    .replace(/```([^`]+)```/g, "<code>$1</code>")
    .replace(/\*([^*\n]+)\*/g, "<strong>$1</strong>")
    .replace(/_([^_\n]+)_/g, "<em>$1</em>")
    .replace(/~([^~\n]+)~/g, "<s>$1</s>")
    .replace(/\{\{([^}]+)\}\}/g, (_m, key) => {
      const varKey = variableMapping?.[key];
      const label = varKey ? eventVarLabels?.[varKey] : null;
      const sample = varKey ? eventVarSamples?.[varKey] : null;
      const display = label
        ? `{${label}}`
        : sample
        ? sample
        : `{value_${key}}`;
      return `<span style="background:#fff3b0;padding:0 3px;border-radius:3px;">${escapeHtml(
        display
      )}</span>`;
    });
};

const findComponent = (components, type) =>
  (components || []).find((c) => (c?.type || "").toUpperCase() === type);

// AUTHENTICATION templates have no merchant-authored body text — WhatsApp
// builds the customer-facing string from the template's flags at send time.
// Synthesize the same wording locally so the preview isn't blank.
//
// Reference shape:
//   "<code> is your verification code." +
//   (add_security_recommendation ? " For your security, do not share this code." : "") +
//   (footer.code_expiration_minutes ? "\nThis code expires in N minutes." : "")
const synthesizeAuthComponents = (components) => {
  const original = components || [];
  const body = original.find((c) => (c?.type || "").toUpperCase() === "BODY") || {};
  const footer = original.find((c) => (c?.type || "").toUpperCase() === "FOOTER") || {};
  const buttons = original.find((c) => (c?.type || "").toUpperCase() === "BUTTONS");

  const securityLine =
    body.add_security_recommendation || body.addSecurityRecommendation
      ? " For your security, do not share this code."
      : "";

  const expiry = footer.code_expiration_minutes || footer.codeExpirationMinutes;

  return [
    // Inline a sample OTP code directly rather than {{1}} — the preview here
    // is illustrative; at send time WhatsApp does the substitution itself.
    {
      type: "BODY",
      text: `1234 is your verification code.${securityLine}`,
    },
    ...(expiry
      ? [{ type: "FOOTER", text: `This code expires in ${expiry} minutes.` }]
      : []),
    ...(buttons
      ? [
          {
            type: "BUTTONS",
            buttons: [
              { type: "URL", text: buttons.buttons?.[0]?.text || "Copy code" },
            ],
          },
        ]
      : []),
  ];
};

const TemplatePreview = ({ template, eventVarSamples, eventVarLabels }) => {
  // AUTHENTICATION templates need synthesized components — see the helper
  // above. Everything else uses the components as Meta returned them.
  const isAuth = (template.category || "").toUpperCase() === "AUTHENTICATION";
  const renderComponents = isAuth
    ? synthesizeAuthComponents(template.components)
    : template.components;

  const header = findComponent(renderComponents, "HEADER");
  const body = findComponent(renderComponents, "BODY");
  const footer = findComponent(renderComponents, "FOOTER");
  const buttonsComp = findComponent(renderComponents, "BUTTONS");
  const buttons = buttonsComp?.buttons || [];
  const mapping = template.variableMapping || {};

  // For a URL button registered as cutty/{{1}}, show a friendlier destination
  // hint based on the persisted url_button intent.
  const urlButtonHint = (() => {
    const ub = template.urlButton;
    if (!ub) return null;
    if (ub.mode === "predefined") return `→ ${ub.variable}`;
    if (ub.mode === "base") return `→ ${ub.base}{${ub.variable}}`;
    return null;
  })();

  return (
    <div
      style={{
        background: "#e5ddd5",
        borderRadius: 8,
        padding: 12,
        minWidth: 260,
        maxWidth: 320,
        boxShadow: "0 6px 20px rgba(0,0,0,0.15)",
        fontFamily: "system-ui, -apple-system, sans-serif",
      }}
    >
      <div
        style={{
          background: "#ffffff",
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
            dangerouslySetInnerHTML={{
              __html: fillSamples(header.text, mapping, eventVarSamples, eventVarLabels) || "&nbsp;",
            }}
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
            {I18n.t("whatsapp_templates_list.format_preview", {
              format:
                header.format.charAt(0) + header.format.slice(1).toLowerCase(),
            })}
          </div>
        )}

        {body && (
          <div>
            {(body.text || "").split("\n").map((line, i) => (
              <div
                key={i}
                dangerouslySetInnerHTML={{
                  __html: fillSamples(line, mapping, eventVarSamples, eventVarLabels) || "&nbsp;",
                }}
              />
            ))}
          </div>
        )}

        {footer && (
          <div style={{ marginTop: 6, fontSize: 11, color: "#667781" }}>
            {footer.text}
          </div>
        )}

        <div style={{ fontSize: 10, color: "#8696a0", textAlign: "right", marginTop: 4 }}>
          {I18n.t("whatsapp_templates_list.12_34_pm")}
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
                  background: "#ffffff",
                  borderRadius: 6,
                  padding: "8px 10px",
                  fontSize: 13,
                  color: "#027eb5",
                  textAlign: "center",
                  fontWeight: 500,
                }}
              >
                {symbol} {b.text || "Button"}
                {type === "URL" && urlButtonHint && (
                  <div style={{ fontSize: 10, color: "#667781", marginTop: 2 }}>
                    {urlButtonHint}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

const PREVIEW_WIDTH = 320;
const PREVIEW_GAP = 12;

// True for one-tap "copy the code to clipboard" buttons. These don't need
// a base URL / suffix configuration — the only variable is the code itself,
// supplied by the template's variable_mapping at send time. We detect both
// the WhatsApp-native structured types (OTP / COPY_CODE used on AUTH
// templates) and merchants who shipped the same UX as a URL button labeled
// "Copy code" on a UTILITY template.
const isCopyCodeButton = (b) => {
  const type = (b?.type || "").toUpperCase();
  if (type === "OTP" || type === "COPY_CODE") return true;
  if (type !== "URL") return false;
  const text = (b?.text || "").trim().toLowerCase();
  return text === "copy" || text === "copy code" || text === "copy otp";
};

// Scan a template's components for body/header {{N}} placeholder positions
// so the editor can show one variable picker per slot.
const findPlaceholderPositions = (template) => {
  const out = new Set();
  (template.components || []).forEach((c) => {
    const type = (c?.type || "").toUpperCase();
    if (type === "BODY" || (type === "HEADER" && (c?.format || "").toUpperCase() === "TEXT")) {
      const text = c.text || "";
      const matches = text.match(/\{\{(\d+)\}\}/g) || [];
      matches.forEach((m) => out.add(m.replace(/[{}]/g, "")));
    }
  });
  return Array.from(out).sort((a, b) => Number(a) - Number(b));
};

// True if the components include a URL button whose URL contains {{N}} AND
// it isn't a one-tap copy-code style button. Copy-code buttons (whether
// Meta-native OTP/COPY_CODE on AUTH templates or a UTILITY URL button
// labeled "Copy code") don't need a base URL or suffix variable picker —
// the code itself is the only dynamic part and comes from variable_mapping.
const hasDynamicUrlButton = (template) => {
  const buttonsComp = (template.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "BUTTONS"
  );
  if (!buttonsComp) return false;
  return (buttonsComp.buttons || []).some(
    (b) =>
      !isCopyCodeButton(b) &&
      (b?.type || "").toUpperCase() === "URL" &&
      (b.url || "").includes("{{")
  );
};

const TemplateBindingEditor = ({ template, events, onClose, onSaved }) => {
  const [eventTypeKey, setEventTypeKey] = useState(template.eventTypeKey || "");
  const [variableMapping, setVariableMapping] = useState(
    template.variableMapping ? { ...template.variableMapping } : {}
  );
  const initialUrlButton = template.urlButton || {};
  const [urlMode, setUrlMode] = useState(initialUrlButton.mode || "none");
  const [urlVariable, setUrlVariable] = useState(initialUrlButton.variable || "");
  const [urlBase, setUrlBase] = useState(initialUrlButton.base || "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  const headerComp = useMemo(
    () =>
      (template.components || []).find(
        (c) => (c?.type || "").toUpperCase() === "HEADER"
      ),
    [template]
  );
  const isImageHeader = (headerComp?.format || "").toUpperCase() === "IMAGE";
  const initialHeaderMedia = template.headerMedia || {};
  const hasFixedHeaderImage =
    !!initialHeaderMedia.mediaId ||
    !!initialHeaderMedia.media_id ||
    !!initialHeaderMedia.url ||
    (initialHeaderMedia.source === "url" && !!initialHeaderMedia.value);
  const [headerMode, setHeaderMode] = useState(
    hasFixedHeaderImage ? "fixed" : "product"
  );
  const [headerImageUrl, setHeaderImageUrl] = useState(
    initialHeaderMedia.url ||
      (initialHeaderMedia.source === "url" ? initialHeaderMedia.value : "") ||
      ""
  );
  const headerUrlValid = /^https?:\/\//i.test(headerImageUrl.trim());
  const headerOk =
    !isImageHeader ||
    headerMode === "product" ||
    (headerMode === "fixed" && headerUrlValid);

  const positions = useMemo(() => findPlaceholderPositions(template), [template]);
  const showsUrlSection = useMemo(() => hasDynamicUrlButton(template), [template]);

  // The button LABEL is fixed by the approved template on Meta — it can't be
  // changed at bind/send time (only the URL's {{1}} value is dynamic). So we
  // read it from the template's components and treat it as a constant rather
  // than letting the merchant edit it here.
  const urlText = useMemo(() => {
    const buttonsComp = (template.components || []).find(
      (c) => (c?.type || "").toUpperCase() === "BUTTONS"
    );
    const urlBtn = (buttonsComp?.buttons || []).find(
      (b) => (b?.type || "").toUpperCase() === "URL"
    );
    return urlBtn?.text || initialUrlButton.text || "";
  }, [template, initialUrlButton.text]);

  const selectedEvent = events.find((e) => e.key === eventTypeKey);
  const allVars = selectedEvent?.variables || [];
  const urlVars = allVars.filter((v) => v.kind === "url");
  const nonUrlVars = allVars.filter((v) => v.kind !== "url");

  // Build sample lookup so the preview fills {{N}} with the friendly sample
  // (e.g. "Aman") for whichever variable is currently mapped to that slot.
  const previewSamples = useMemo(() => {
    const out = {};
    allVars.forEach((v) => {
      out[v.key] = v.sample;
    });
    return out;
  }, [allVars]);

  // Same shape, but with the merchant-facing variable label — preview renders
  // `{customer first name}` instead of `Aman` so the merchant sees the FIELD.
  const previewLabels = useMemo(() => {
    const out = {};
    allVars.forEach((v) => {
      out[v.key] = (v.label || "").toLowerCase();
    });
    return out;
  }, [allVars]);

  // Synthetic template snapshot that mirrors what would be saved — so the
  // preview reflects what's currently in the modal, not the persisted row.
  const previewTemplate = useMemo(() => {
    let urlButton = null;
    if (showsUrlSection && urlMode === "predefined" && urlVariable) {
      urlButton = { mode: "predefined", variable: urlVariable, text: urlText };
    } else if (showsUrlSection && urlMode === "base" && urlBase && urlVariable) {
      urlButton = { mode: "base", base: urlBase, variable: urlVariable, text: urlText };
    }
    return {
      ...template,
      variableMapping,
      urlButton,
    };
  }, [template, variableMapping, showsUrlSection, urlMode, urlVariable, urlBase, urlText]);

  const handleSave = async () => {
    setSaving(true);
    setError("");
    const payload = {
      event_type_key: eventTypeKey || null,
      variable_mapping: variableMapping,
    };
    const preservedFallback =
      initialUrlButton.fallbackVariable || initialUrlButton.fallback_variable;
    const fallbackPart = preservedFallback
      ? { fallback_variable: preservedFallback }
      : {};
    if (showsUrlSection && urlMode === "predefined") {
      payload.url_button = { mode: "predefined", variable: urlVariable, text: urlText, ...fallbackPart };
    } else if (showsUrlSection && urlMode === "base") {
      payload.url_button = {
        mode: "base",
        base: urlBase,
        variable: urlVariable,
        text: urlText,
        ...fallbackPart,
      };
    } else {
      payload.url_button = null;
    }

    if (isImageHeader) {
      payload.header_media =
        headerMode === "fixed"
          ? { mode: "fixed", source: "url", url: headerImageUrl.trim() }
          : { mode: "order_product_image" };
    }

    try {
      const token = await window.shopify?.idToken?.();
      const resp = await fetch(
        `https://${process.env.APP_HOST}/api/whatsapp/templates/${template.id}`,
        {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            ...(token ? { Authorization: `Bearer ${token}` } : {}),
          },
          body: JSON.stringify(payload),
        }
      );
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(data?.error || `Save failed (${resp.status})`);
      onSaved(data.template);
    } catch (err) {
      setError(err?.message || "Save failed");
    } finally {
      setSaving(false);
    }
  };

  const eventOptions = [
    { label: I18n.t("whatsapp_templates_list.not_bound_to_any_event"), value: "" },
    ...events.map((e) => ({ label: `${e.label} (${e.templateCategory})`, value: e.key })),
  ];

  return (
    <Modal
      open
      onClose={onClose}
      title={`Change variables — ${template.name} (${template.language})`}
      primaryAction={{ content: I18n.t("whatsapp_templates_list.save"), onAction: handleSave, loading: saving, disabled: !headerOk }}
      secondaryActions={[{ content: I18n.t("whatsapp_templates_list.cancel"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="400">
          {error && <Banner tone="critical">{error}</Banner>}

          <Select
            label={I18n.t("whatsapp_templates_list.event_type")}
            options={eventOptions}
            value={eventTypeKey}
            onChange={(v) => {
              setEventTypeKey(v);
              setVariableMapping({}); // reset mapping when event changes
              setUrlVariable("");
            }}
            helpText={
              selectedEvent
                ? `Category locked to ${selectedEvent.templateCategory}. Variables below come from this event.`
                : "Pick the event this template responds to. Variable choices update accordingly."
            }
          />

          {positions.length > 0 && eventTypeKey && (
            <>
              <Divider />
              <Text as="h3" variant="headingSm">
                {I18n.t("whatsapp_templates_list.variables_slots", {
                  count: positions.length,
                })}
              </Text>
              <Text tone="subdued" as="p" variant="bodySm">
                {I18n.t("whatsapp_templates_list.pick_variable_per_placeholder")}
              </Text>
              {positions.map((p) => (
                <Select
                  key={p}
                  label={`{{${p}}}`}
                  options={[
                    { label: I18n.t("whatsapp_templates_list.choose_a_variable"), value: "" },
                    ...allVars.map((v) => ({ label: v.label, value: v.key })),
                  ]}
                  value={variableMapping[p] || ""}
                  onChange={(v) =>
                    setVariableMapping((prev) => ({ ...prev, [p]: v }))
                  }
                />
              ))}
            </>
          )}

          {isImageHeader && eventTypeKey && (
            <>
              <Divider />
              <Text as="h3" variant="headingSm">
                {I18n.t("whatsapp_templates_list.header_image")}
              </Text>
              <Select
                label={I18n.t("whatsapp_templates_list.what_image_should_this_notification_send")}
                options={[
                  { label: I18n.t("whatsapp_templates_list.the_product_image_from_this_event"), value: "product" },
                  { label: I18n.t("whatsapp_templates_list.a_fixed_image_same_every_time"), value: "fixed" },
                ]}
                value={headerMode}
                onChange={setHeaderMode}
              />
              {headerMode === "product" ? (
                <Banner tone="info">
                  {I18n.t("whatsapp_templates_list.the_product_image_from_the_order")}
                </Banner>
              ) : (
                <TextField
                  label={I18n.t("whatsapp_templates_list.image_url")}
                  value={headerImageUrl}
                  onChange={setHeaderImageUrl}
                  autoComplete="off"
                  placeholder="https://…/banner.jpg"
                  helpText={I18n.t("whatsapp_templates_list.a_public_jpg_or_png_we")}
                  error={
                    headerImageUrl.trim() && !headerUrlValid
                      ? "Enter a full https:// image URL"
                      : undefined
                  }
                />
              )}
            </>
          )}

          {eventTypeKey && (
            <>
              <Divider />
              <Text as="h3" variant="headingSm">
                {I18n.t("whatsapp_templates_list.preview")}
              </Text>
              <Text tone="subdued" as="p" variant="bodySm">
                {I18n.t("whatsapp_templates_list.live_preview_using_the_sample_values")}
              </Text>
              <Box paddingBlockStart="200">
                <TemplatePreview
                  template={previewTemplate}
                  eventVarSamples={previewSamples}
                  eventVarLabels={previewLabels}
                />
              </Box>
            </>
          )}

          {showsUrlSection && eventTypeKey && (
            <>
              <Divider />
              <Text as="h3" variant="headingSm">
                {I18n.t("whatsapp_templates_list.url_button")}
              </Text>
              <Text tone="subdued" as="p" variant="bodySm">
                {I18n.t("whatsapp_templates_list.url_button_placeholder_required")}
              </Text>
              <Select
                label={I18n.t("whatsapp_templates_list.link_behaviour")}
                options={[
                  { label: I18n.t("whatsapp_templates_list.don_t_configure_will_fail_at"), value: "none" },
                  {
                    label: I18n.t("whatsapp_templates_list.use_a_known_link_variable"),
                    value: "predefined",
                    disabled: urlVars.length === 0,
                  },
                  { label: I18n.t("whatsapp_templates_list.base_url_variable"), value: "base" },
                ]}
                value={urlMode}
                onChange={setUrlMode}
              />
              {urlMode !== "none" && urlText && (
                <Text as="p" tone="subdued" variant="bodySm">
                  {I18n.t("whatsapp_templates_list.button_label")} <strong>{urlText}</strong> {I18n.t("whatsapp_templates_list.fixed_by_the_approved_template_only")}
                </Text>
              )}
              {urlMode === "predefined" && (
                <Select
                  label={I18n.t("whatsapp_templates_list.link_variable")}
                  options={[
                    { label: I18n.t("whatsapp_templates_list.choose"), value: "" },
                    ...urlVars.map((v) => ({ label: v.label, value: v.key })),
                  ]}
                  value={urlVariable}
                  onChange={setUrlVariable}
                />
              )}
              {urlMode === "base" && (
                <>
                  <TextField
                    label={I18n.t("whatsapp_templates_list.base_url")}
                    value={urlBase}
                    onChange={setUrlBase}
                    autoComplete="off"
                    placeholder="https://shop.com/orders/"
                  />
                  <Select
                    label={I18n.t("whatsapp_templates_list.suffix_variable")}
                    options={[
                      { label: I18n.t("whatsapp_templates_list.choose"), value: "" },
                      ...nonUrlVars.map((v) => ({ label: v.label, value: v.key })),
                    ]}
                    value={urlVariable}
                    onChange={setUrlVariable}
                  />
                </>
              )}
            </>
          )}
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

// Popup to fire a one-off test send of a template to a phone number the
// merchant types in. The backend (Meta::TestMessageService) auto-fills sample
// values for every {{N}} body/header/button slot, so all we collect here is the
// recipient — no variable entry needed.
const TestSendModal = ({ template, onClose }) => {
  const [to, setTo] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  const [, postSend] = useApi(
    { url: "/api/whatsapp/test_messages", method: "POST" },
    { manual: true }
  );

  const canSend = to.trim().length > 0 && !sending;

  const handleSend = async () => {
    setError("");
    setSuccess("");
    if (!canSend) return;
    setSending(true);
    try {
      const { data } = await postSend({
        data: {
          to: to.trim(),
          template_name: template.name,
          language: template.language,
        },
      });
      setSuccess(`Sent. Message id: ${data?.messageId || "ok"}`);
    } catch (err) {
      setError(
        err?.response?.data?.error || err?.message || "Send failed"
      );
    } finally {
      setSending(false);
    }
  };

  return (
    <Modal
      open
      onClose={onClose}
      title={`Send test — ${template.name} (${template.language})`}
      primaryAction={{
        content: I18n.t("whatsapp_templates_list.send_test"),
        onAction: handleSend,
        loading: sending,
        disabled: !canSend,
      }}
      secondaryActions={[{ content: I18n.t("whatsapp_templates_list.close"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="300">
          {error && <Banner tone="critical">{error}</Banner>}
          {success && (
            <Banner tone="success" onDismiss={() => setSuccess("")}>
              {success}
            </Banner>
          )}
          <Text as="p" tone="subdued" variant="bodySm">
            {I18n.t("whatsapp_templates_list.sends_this_template_to_the_number")}
          </Text>
          <TextField
            label={I18n.t("whatsapp_templates_list.recipient_with_country_code")}
            placeholder="e.g. 919999988888"
            value={to}
            onChange={setTo}
            autoComplete="tel"
            inputMode="tel"
          />
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

// Hover popover that anchors next to a row but stays inside the viewport.
// We position with `position: fixed` from the row's bounding rect; then after
// mount we measure the popover's actual height and shift `top` upward if it
// would otherwise spill past the bottom of the visible window. Without this,
// hovering a row near the page bottom clipped the preview.
const HoverPreviewPortal = ({ top, left, template, samples, labels }) => {
  const ref = useRef(null);
  const [adjustedTop, setAdjustedTop] = useState(top);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const vh = window.innerHeight;
    const h = el.offsetHeight;
    const margin = 16;
    // If anchoring at row.top would overflow, lift the popover so its bottom
    // sits `margin`px above the viewport bottom — but never push it above the
    // top of the viewport.
    const maxTop = vh - h - margin;
    setAdjustedTop(Math.max(margin, Math.min(top, maxTop)));
  }, [top, template]);

  return (
    <div
      ref={ref}
      style={{
        position: "fixed",
        top: adjustedTop,
        left,
        width: PREVIEW_WIDTH,
        maxHeight: `calc(100vh - 32px)`,
        overflowY: "auto",
        zIndex: 1000,
        pointerEvents: "none",
      }}
    >
      <TemplatePreview
        template={template}
        eventVarSamples={samples}
        eventVarLabels={labels}
      />
    </div>
  );
};

// Edits the template's content on Meta (body text, header text, footer text,
// button text). Body changes flow into a re-derived variable mapping so that
// freshly-added {{N}} positions get a friendly variable assigned before the
// template is re-submitted for review.
const EditTemplateModal = ({ template, events, onClose, onSaved }) => {
  const originalBody = (template.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "BODY"
  );
  const originalFooter = (template.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "FOOTER"
  );
  const originalHeader = (template.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "HEADER"
  );
  const originalButtons = (template.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "BUTTONS"
  );

  const headerFormat = (originalHeader?.format || "").toUpperCase();
  const hasTextHeader = headerFormat === "TEXT";

  const [bodyText, setBodyText] = useState(originalBody?.text || "");
  const [footerText, setFooterText] = useState(originalFooter?.text || "");
  const [headerText, setHeaderText] = useState(originalHeader?.text || "");
  const [buttonTexts, setButtonTexts] = useState(
    (originalButtons?.buttons || []).map((b) => b.text || "")
  );

  // Reuse the variable mapping but drop positions the merchant just removed,
  // and surface a Select for any newly-added position.
  const [mapping, setMapping] = useState(template.variableMapping || {});

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const positions = useMemo(() => {
    const seen = new Set();
    (bodyText.match(/\{\{(\d+)\}\}/g) || []).forEach((m) =>
      seen.add(m.replace(/[{}]/g, ""))
    );
    return Array.from(seen).sort((a, b) => Number(a) - Number(b));
  }, [bodyText]);

  const event = events.find((e) => e.key === template.eventTypeKey);
  const eventVars = event?.variables || [];

  const effectiveMapping = useMemo(() => {
    const next = {};
    positions.forEach((p) => {
      if (mapping[p]) next[p] = mapping[p];
    });
    return next;
  }, [positions, mapping]);

  const handleSubmit = async () => {
    setError("");
    if (!bodyText.trim()) {
      setError("Body text is required.");
      return;
    }
    if (positions.some((p) => !effectiveMapping[p])) {
      setError("Every {{N}} placeholder must be mapped to a variable.");
      return;
    }

    setSubmitting(true);
    try {
      // Re-build components from edits while preserving non-editable parts
      // (BUTTONS structure beyond text, header media format, etc.).
      const components = (template.components || []).map((c) => {
        const t = (c?.type || "").toUpperCase();
        if (t === "BODY") {
          const next = { type: "BODY", text: bodyText };
          if (positions.length) {
            next.example = {
              body_text: [
                positions.map((p) => {
                  const v = eventVars.find((x) => x.key === effectiveMapping[p]);
                  return v?.sample || `value_${p}`;
                }),
              ],
            };
          }
          return next;
        }
        if (t === "FOOTER") return { type: "FOOTER", text: footerText };
        if (t === "HEADER" && hasTextHeader) {
          return { type: "HEADER", format: "TEXT", text: headerText };
        }
        if (t === "BUTTONS") {
          return {
            type: "BUTTONS",
            buttons: (c.buttons || []).map((b, i) => ({
              ...b,
              text: buttonTexts[i] ?? b.text,
            })),
          };
        }
        return c;
      });

      const payload = {
        components,
        variable_mapping: effectiveMapping,
        url_button: template.urlButton || undefined,
        header_media: template.headerMedia || undefined,
      };

      const { data } = await Api.post(
        `https://${process.env.APP_HOST}/api/whatsapp/templates/${template.id}/meta_edit`,
        payload
      );
      onSaved(data?.template);
    } catch (err) {
      setError(
        err?.response?.data?.error ||
          err?.message ||
          "Failed to submit changes to Meta."
      );
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Modal
      open
      onClose={onClose}
      title={`Edit template — ${template.name} (${template.language})`}
      primaryAction={{
        content: I18n.t("whatsapp_templates_list.submit_changes_to_meta"),
        onAction: handleSubmit,
        loading: submitting,
      }}
      secondaryActions={[{ content: I18n.t("whatsapp_templates_list.cancel"), onAction: onClose }]}
      large
    >
      <Modal.Section>
        <BlockStack gap="400">
          {error && <Banner tone="critical">{error}</Banner>}

          <Banner tone="info">
            {I18n.t("whatsapp_templates_list.editing_sends_the_template_back_through")} <strong>{I18n.t("whatsapp_templates_list.pending")}</strong> {I18n.t("whatsapp_templates_list.until_approved_meta_allows_up_to")}
          </Banner>

          {hasTextHeader && (
            <TextField
              label={I18n.t("whatsapp_templates_list.header_text")}
              value={headerText}
              onChange={setHeaderText}
              maxLength={60}
              showCharacterCount
              autoComplete="off"
            />
          )}

          <TextField
            label={I18n.t("whatsapp_templates_list.body")}
            value={bodyText}
            onChange={setBodyText}
            multiline={5}
            autoComplete="off"
            maxLength={1024}
            showCharacterCount
            helpText={I18n.t("whatsapp_templates_list.use_for_variables_each_placeholder_gets")}
          />

          {originalFooter && (
            <TextField
              label={I18n.t("whatsapp_templates_list.footer")}
              value={footerText}
              onChange={setFooterText}
              maxLength={60}
              showCharacterCount
              autoComplete="off"
            />
          )}

          {buttonTexts.length > 0 && (
            <BlockStack gap="200">
              <Text as="h3" variant="headingSm">
                {I18n.t("whatsapp_templates_list.buttons")}
              </Text>
              {buttonTexts.map((txt, i) => (
                <TextField
                  key={i}
                  label={`Button ${i + 1} text`}
                  value={txt}
                  onChange={(v) =>
                    setButtonTexts((prev) => {
                      const next = [...prev];
                      next[i] = v;
                      return next;
                    })
                  }
                  maxLength={25}
                  showCharacterCount
                  autoComplete="off"
                />
              ))}
            </BlockStack>
          )}

          {positions.length > 0 && (
            <BlockStack gap="200">
              <Text as="h3" variant="headingSm">
                {I18n.t("whatsapp_templates_list.variables_count", {
                  count: positions.length,
                })}
              </Text>
              <Text as="p" tone="subdued" variant="bodySm">
                {I18n.t("whatsapp_templates_list.confirm_which_event_variable_fills_each")}
              </Text>
              {positions.map((p) => (
                <Select
                  key={p}
                  label={`{{${p}}}`}
                  options={[
                    { label: I18n.t("whatsapp_templates_list.choose_a_variable"), value: "" },
                    ...eventVars.map((v) => ({ label: v.label, value: v.key })),
                  ]}
                  value={effectiveMapping[p] || ""}
                  onChange={(v) => setMapping((prev) => ({ ...prev, [p]: v }))}
                />
              ))}
            </BlockStack>
          )}
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

const WhatsappTemplatesList = () => {
  const [templates, setTemplates] = useState([]);
  const [state, setState] = useState({ loading: false, error: "", loaded: false });
  const [hovered, setHovered] = useState(null); // { id, top, left }
  const [editingId, setEditingId] = useState(null);
  const [testingId, setTestingId] = useState(null);
  // Separate from `editingId` (variables/event mapping). When set, opens the
  // EditTemplateModal which edits the actual template content on Meta.
  const [editingMetaId, setEditingMetaId] = useState(null);
  // 0 = In use (bound to an event), 1 = Other (everything else).
  const [activeSection, setActiveSection] = useState(0);

  // Compute popover screen position from the hovered row's bounding rect.
  // Prefers right side; flips left when it would overflow the viewport.
  const positionFor = (rowEl) => {
    const rect = rowEl.getBoundingClientRect();
    const spaceRight = window.innerWidth - rect.right;
    const fitsRight = spaceRight >= PREVIEW_WIDTH + PREVIEW_GAP + 8;
    const left = fitsRight
      ? rect.right + PREVIEW_GAP
      : Math.max(8, rect.left - PREVIEW_WIDTH - PREVIEW_GAP);
    return { top: rect.top, left };
  };

  const [{ data: account }] = useApi(
    { url: "/api/whatsapp/account", method: "GET" },
    { manual: false }
  );
  const [{ data: eventsData }] = useApi(
    { url: "/api/whatsapp/events", method: "GET" },
    { manual: false }
  );
  const [, listTemplatesApi] = useApi(
    { url: "/api/whatsapp/templates", method: "GET" },
    { manual: true }
  );
  const [, syncTemplatesApi] = useApi(
    { url: "/api/whatsapp/templates/sync", method: "POST" },
    { manual: true }
  );

  // var.key → sample text, scoped per event. Used to fill {{N}} slots in the preview.
  const eventVarSamplesByEvent = useMemo(() => {
    const out = {};
    (eventsData?.events || []).forEach((e) => {
      const map = {};
      (e.variables || []).forEach((v) => {
        map[v.key] = v.sample;
      });
      out[e.key] = map;
    });
    return out;
  }, [eventsData]);

  // var.key → friendly merchant-facing label, scoped per event. Used to render
  // {customer first name}-style placeholders inside the preview, so the
  // merchant sees the FIELD instead of an example value.
  const eventVarLabelsByEvent = useMemo(() => {
    const out = {};
    (eventsData?.events || []).forEach((e) => {
      const map = {};
      (e.variables || []).forEach((v) => {
        map[v.key] = (v.label || "").toLowerCase();
      });
      out[e.key] = map;
    });
    return out;
  }, [eventsData]);

  const accountReady = account?.connected && account?.status === "verified";

  const load = useCallback(
    async ({ remoteSync = false } = {}) => {
      if (!accountReady) return;
      setState({ loading: true, error: "", loaded: false });
      try {
        const fn = remoteSync ? syncTemplatesApi : listTemplatesApi;
        const { data } = await fn();
        setTemplates(Array.isArray(data?.templates) ? data.templates : []);
        setState({ loading: false, error: "", loaded: true });
      } catch (err) {
        setState({
          loading: false,
          error:
            err?.response?.data?.error ||
            err?.message ||
            "Failed to load templates.",
          loaded: true,
        });
      }
    },
    [accountReady, listTemplatesApi, syncTemplatesApi]
  );

  useEffect(() => {
    if (accountReady) load();
  }, [accountReady, load]);

  // Refresh when a template is created elsewhere on the page.
  useEffect(() => {
    const handler = () => load({ remoteSync: true });
    window.addEventListener("whatsapp:template-created", handler);
    return () => window.removeEventListener("whatsapp:template-created", handler);
  }, [load]);

  if (!accountReady) {
    return (
      <Card>
        <Box padding="500">
          <EmptyState
            heading={I18n.t("whatsapp_templates_list.connect_a_verified_whatsapp_account_first")}
            action={{ content: I18n.t("whatsapp_templates_list.go_to_account"), url: "/features/whatsapp/account" }}
            image="https://cdn.shopify.com/s/files/1/0262/4071/2726/files/emptystate-files.png"
          >
            <Text as="p" tone="subdued">
              {I18n.t("whatsapp_templates_list.once_your_account_is_verified_your")}
            </Text>
          </EmptyState>
        </Box>
      </Card>
    );
  }

  // "In use" means an active binding actually exists (the green badge), so only
  // those messages will fire. A template that merely carries a default
  // event_type_key but no binding is not in use and belongs under "Other".
  const inUse = templates.filter((t) => t.bound);
  const other = templates.filter((t) => !t.bound);
  const sectionTabs = [
    {
      id: "in-use",
      content: `In use${inUse.length ? ` (${inUse.length})` : ""}`,
      panelID: "templates-in-use",
    },
    {
      id: "other",
      content: `Other templates${other.length ? ` (${other.length})` : ""}`,
      panelID: "templates-other",
    },
  ];
  const visible = activeSection === 0 ? inUse : other;
  const emptySectionCopy =
    activeSection === 0
      ? "No templates are wired to a notification yet. Switch to the Notifications tab to enable one."
      : "Everything you have is already in use. Create a new template or pick a pre-made one to add more.";

  return (
    <Card padding="600">
        <BlockStack gap="300">
          <InlineStack align="space-between" blockAlign="center">
            <Text as="h2" variant="headingMd">
              {I18n.t("whatsapp_templates_list.your_whatsapp_templates")}
            </Text>
            <Button
              icon={RefreshMinor}
              onClick={() => load({ remoteSync: true })}
              disabled={state.loading}
              loading={state.loading}
            >
              {I18n.t("whatsapp_templates_list.refresh")}
            </Button>
          </InlineStack>

          {state.error && <Banner tone="critical">{state.error}</Banner>}

          {state.loading && !templates.length && (
            <Box padding="600">
              <InlineStack align="center" gap="200">
                <Spinner size="small" accessibilityLabel={I18n.t("whatsapp_templates_list.loading_templates")} />
                <Text as="span" tone="subdued">
                  {I18n.t("whatsapp_templates_list.loading_templates_from_whatsapp")}
                </Text>
              </InlineStack>
            </Box>
          )}

          {!state.loading && templates.length === 0 && state.loaded && !state.error && (
            <Box padding="600">
              <Text tone="subdued" as="p" alignment="center">
                {I18n.t("whatsapp_templates_list.no_templates_found_for_this_waba")}
              </Text>
            </Box>
          )}

          {templates.length > 0 && (
            <>
              <Tabs
                tabs={sectionTabs}
                selected={activeSection}
                onSelect={setActiveSection}
                fitted
              />

              {visible.length === 0 ? (
                <Box padding="600">
                  <Text tone="subdued" as="p" alignment="center" variant="bodySm">
                    {emptySectionCopy}
                  </Text>
                </Box>
              ) : (
                <BlockStack gap="200">
                  {visible.map((t) => {
                    const rowKey = `${t.id}-${t.language}`;
                    const statusUpper = String(t.status || "").toUpperCase();
                    const isApproved = statusUpper === "APPROVED";
                    const isEditable = ["approved", "rejected", "paused"].includes(t.status);
                    // Use a tone-coded left accent stripe so status reads at a
                    // glance — green for approved/in-use, amber for pending,
                    // red for rejected/disabled. Same palette as the status badge.
                    const accent =
                      statusTone(t.status) === "success"
                        ? "#1f8b4d"
                        : statusTone(t.status) === "attention"
                        ? "#b58300"
                        : statusTone(t.status) === "critical"
                        ? "#c0392b"
                        : "#5c5f62";
                    return (
                      <div
                        key={rowKey}
                        onMouseEnter={(e) =>
                          setHovered({ id: rowKey, ...positionFor(e.currentTarget) })
                        }
                        onMouseLeave={() =>
                          setHovered((cur) => (cur?.id === rowKey ? null : cur))
                        }
                        style={{
                          borderLeft: `3px solid ${accent}`,
                          borderRadius: 8,
                          background: "#fff",
                          boxShadow: "0 1px 0 rgba(0,0,0,0.04)",
                        }}
                      >
                        <Box
                          padding="300"
                          borderColor="border"
                          borderWidth="025"
                          borderRadius="200"
                        >
                          <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
                            <BlockStack gap="100">
                              <InlineStack gap="200" blockAlign="center" wrap>
                                <Text as="span" variant="bodyMd" fontWeight="semibold">
                                  {t.name}
                                </Text>
                                <Badge tone={statusTone(t.status)}>{statusLabel(t.status)}</Badge>
                                {t.category && <Badge tone="info">{t.category}</Badge>}
                                {t.bound && <Badge tone="success">{I18n.t("whatsapp_templates_list.in_use")}</Badge>}
                              </InlineStack>
                              <Text as="span" tone="subdued" variant="bodySm">
                                {t.eventTypeKey
                                  ? `Sends on: ${t.eventTypeKey.replace(/_/g, " ")} · `
                                  : ""}
                                {t.language}
                                {t.metaTemplateId ? ` · Meta ID: ${t.metaTemplateId}` : ""}
                              </Text>
                            </BlockStack>
                            <InlineStack gap="200" blockAlign="center">
                              {isApproved && (
                                <Button
                                  variant="plain"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    setTestingId(rowKey);
                                  }}
                                >
                                  {I18n.t("whatsapp_templates_list.test")}
                                </Button>
                              )}
                              <Button
                                variant="plain"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setEditingId(rowKey);
                                }}
                              >
                                {t.eventTypeKey ? "Change variables" : "Enable"}
                              </Button>
                              {isEditable && (
                                <Button
                                  variant="plain"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    setEditingMetaId(rowKey);
                                  }}
                                >
                                  {I18n.t("whatsapp_templates_list.edit_template")}
                                </Button>
                              )}
                            </InlineStack>
                          </InlineStack>
                        </Box>
                      </div>
                    );
                  })}
                </BlockStack>
              )}
            </>
          )}

          {editingId &&
            (() => {
              const editingTemplate = templates.find(
                (x) => `${x.id}-${x.language}` === editingId
              );
              if (!editingTemplate) return null;
              return (
                <TemplateBindingEditor
                  template={editingTemplate}
                  events={eventsData?.events || []}
                  onClose={() => setEditingId(null)}
                  onSaved={(saved) => {
                    setTemplates((prev) =>
                      prev.map((p) => (p.id === saved.id ? saved : p))
                    );
                    setEditingId(null);
                  }}
                />
              );
            })()}

          {testingId &&
            (() => {
              const testingTemplate = templates.find(
                (x) => `${x.id}-${x.language}` === testingId
              );
              if (!testingTemplate) return null;
              return (
                <TestSendModal
                  template={testingTemplate}
                  onClose={() => setTestingId(null)}
                />
              );
            })()}

          {editingMetaId &&
            (() => {
              const editingTemplate = templates.find(
                (x) => `${x.id}-${x.language}` === editingMetaId
              );
              if (!editingTemplate) return null;
              return (
                <EditTemplateModal
                  template={editingTemplate}
                  events={eventsData?.events || []}
                  onClose={() => setEditingMetaId(null)}
                  onSaved={(saved) => {
                    setTemplates((prev) =>
                      prev.map((p) => (p.id === saved.id ? saved : p))
                    );
                    setEditingMetaId(null);
                  }}
                />
              );
            })()}

          {hovered &&
            ReactDOM.createPortal(
              (() => {
                const t = templates.find(
                  (x) => `${x.id}-${x.language}` === hovered.id
                );
                if (!t) return null;
                const samples = eventVarSamplesByEvent[t.eventTypeKey] || {};
                const labels = eventVarLabelsByEvent[t.eventTypeKey] || {};
                return (
                  <HoverPreviewPortal
                    top={hovered.top}
                    left={hovered.left}
                    template={t}
                    samples={samples}
                    labels={labels}
                  />
                );
              })(),
              document.body
            )}
        </BlockStack>
      
    </Card>
  );
};

export default WhatsappTemplatesList;

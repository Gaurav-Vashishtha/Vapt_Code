import React, { useEffect, useMemo, useRef, useState } from "react";
import useApi from "../../Hooks/useApi";
import {
  Card,
  BlockStack,
  InlineStack,
  Box,
  Text,
  TextField,
  Select,
  Button,
  Tag,
  Icon,
  ButtonGroup,
  Layout,
  Banner,
  EmptyState,
} from "@shopify/polaris";
import {
  PlusMinor,
  DeleteMinor,
} from "@shopify/polaris-icons";
import I18n from "../../i18n-lang";

const CATEGORY_OPTIONS = [
  { get label() {
      return I18n.t("whatsapp_template_create_tab.utility");
    }, value: "UTILITY" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.marketing");
    }, value: "MARKETING" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.authentication");
    }, value: "AUTHENTICATION" },
];

const HEADER_TYPE_OPTIONS = [
  { get label() {
      return I18n.t("whatsapp_template_create_tab.none");
    }, value: "none" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.text");
    }, value: "text" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.image");
    }, value: "image" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.video");
    }, value: "video" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.document");
    }, value: "document" },
];

const LANGUAGE_OPTIONS = [
  { get label() {
      return I18n.t("whatsapp_template_create_tab.english");
    }, value: "en" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.english_uk");
    }, value: "en_GB" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.english_us");
    }, value: "en_US" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.hindi");
    }, value: "hi" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.spanish");
    }, value: "es" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.french");
    }, value: "fr" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.german");
    }, value: "de" },
  { get label() {
      return I18n.t("whatsapp_template_create_tab.arabic");
    }, value: "ar" },
];

const MAX_BODY_LENGTH = 1024;
const MAX_FOOTER_LENGTH = 60;
const MAX_HEADER_LENGTH = 60;

// Templates now route through Rails using the per-shop WhatsappAccount token.
// No env vars needed on the client.

const escapeHtml = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const formatPreviewLine = (line, examples = {}) => {
  let html = escapeHtml(line)
    .replace(/```([^`]+)```/g, "<code>$1</code>")
    .replace(/\*([^*\n]+)\*/g, "<strong>$1</strong>")
    .replace(/_([^_\n]+)_/g, "<em>$1</em>")
    .replace(/~([^~\n]+)~/g, "<s>$1</s>")
    .replace(/\{\{([^}]+)\}\}/g, (_match, key) => {
      const filled = (examples[key] || "").toString().trim();
      const display = filled.length ? escapeHtml(filled) : `{{${escapeHtml(key)}}}`;
      return `<span style="background:#fff3b0;padding:0 3px;border-radius:3px;">${display}</span>`;
    });
  return html;
};

const extractVariables = (text) => {
  if (!text) return [];
  const matches = text.match(/\{\{([^}]+)\}\}/g) || [];
  return matches.map((m) => m.replace(/[{}]/g, ""));
};

const placeholderForVariable = (key) => {
  if (/^\d+$/.test(key)) return `value_${key}`;
  return `sample_${key}`;
};

// Events whose payload carries line-item product data we can pull an image
// out of at send time. Keep in sync with
// app/services/whatsapp/order_product_image_resolver.rb (the server-side
// source of truth — this list just gates the UI option).
const ORDER_PRODUCT_IMAGE_EVENTS = [
  "order_created",
  "order_fulfilled",
  "first_time_purchase",
  "abandoned_cart",
  "cod_verification",
  "cod_verification_reminder",
  "order_cancelled",
  "order_out_for_delivery",
  "order_delivered",
  "feedback_request",
  "reorder_reminder",
];

const buildComponentsPayload = ({
  headerType,
  headerText,
  headerMediaUrl,
  body,
  footer,
  buttons,
  bodyExamples = {},
  headerExamples = {},
}) => {
  const components = [];
  const sample = (examples, key) =>
    (examples[key] || "").trim() || placeholderForVariable(key);

  if (headerType !== "none") {
    const header = { type: "HEADER", format: headerType.toUpperCase() };
    if (headerType === "text") {
      header.text = headerText || "";
      const headerVars = extractVariables(headerText);
      if (headerVars.length) {
        header.example = {
          header_text: headerVars.map((k) => sample(headerExamples, k)),
        };
      }
    } else if (["image", "video", "document"].includes(headerType) && headerMediaUrl) {
      // Meta expects example.header_handle to be a media handle from their
      // Resumable Upload API — a raw public URL is rejected on strict accounts.
      // In upload mode the caller passes the resumable handle as headerMediaUrl.
      // In "paste a URL" mode it's the public URL, which the backend
      // (Meta::TemplateService) downloads and resolves to a real handle before
      // the create call; the URL is still persisted for send-time media.
      header.example = { header_handle: [headerMediaUrl] };
    }
    components.push(header);
  }

  if (body) {
    const bodyComponent = { type: "BODY", text: body };
    const bodyVars = extractVariables(body);
    if (bodyVars.length) {
      bodyComponent.example = {
        body_text: [bodyVars.map((k) => sample(bodyExamples, k))],
      };
    }
    components.push(bodyComponent);
  }

  if (footer) {
    components.push({ type: "FOOTER", text: footer });
  }

  if (buttons.length > 0) {
    components.push({
      type: "BUTTONS",
      buttons: buttons.map((b) => {
        if (b.type === "url") {
          // For static URLs (no variable) we forward as-is.
          // For predefined/base modes, the backend rewrites the URL/example
          // to https://cutt.ly/{{1}} before posting to Meta — we still need to
          // send a syntactically-valid component, so use the cutly form here too.
          if (b.urlMode === "predefined" || b.urlMode === "base") {
            return {
              type: "URL",
              text: b.text,
              url: "https://cutt.ly/{{1}}",
              example: ["https://cutt.ly/abc123"],
            };
          }
          const out = { type: "URL", text: b.text, url: b.url };
          const urlVars = extractVariables(b.url);
          if (urlVars.length) out.example = urlVars.map(placeholderForVariable);
          return out;
        }
        if (b.type === "phone_number") {
          return {
            type: "PHONE_NUMBER",
            text: b.text,
            phone_number: b.url,
          };
        }
        return { type: "QUICK_REPLY", text: b.text };
      }),
    });
  }

  return components;
};

// Pull the url_button config out of the first URL button that has a dynamic mode.
// Returns null when there's no dynamic URL button (static-only or no URL button at all).
const buildUrlButtonPayload = (buttons) => {
  const dyn = buttons.find(
    (b) => b.type === "url" && (b.urlMode === "predefined" || b.urlMode === "base"),
  );
  if (!dyn) return null;
  if (dyn.urlMode === "predefined") {
    if (!dyn.urlVariable) return null;
    return { text: dyn.text, mode: "predefined", variable: dyn.urlVariable };
  }
  if (!dyn.urlBase || !dyn.urlVariable) return null;
  return { text: dyn.text, mode: "base", base: dyn.urlBase, variable: dyn.urlVariable };
};

const WhatsappTemplateCreateTab = () => {
  const [name, setName] = useState("");
  const [category, setCategory] = useState("UTILITY");
  const [eventTypeKey, setEventTypeKey] = useState("");
  const [languages, setLanguages] = useState(["en_US"]);
  const [showLangPicker, setShowLangPicker] = useState(false);
  const [bodyExamples, setBodyExamples] = useState({});
  const [headerExamples, setHeaderExamples] = useState({});
  // { "1": "customer.first", "2": "order.id" } — position in template → variable key from event.
  const [variableMapping, setVariableMapping] = useState({});

  const [headerType, setHeaderType] = useState("none");
  const [headerText, setHeaderText] = useState("");
  // "url" | "upload" | "order_product"
  // - url: paste a public URL
  // - upload: upload a static file
  // - order_product: at send time, use the first product image from the order
  //   (or checkout, for abandoned_cart). We still need a sample image for Meta's
  //   template review, so we auto-pick one from the merchant's Shopify products.
  const [headerMediaSource, setHeaderMediaSource] = useState("url");
  const [headerMediaUrl, setHeaderMediaUrl] = useState("");
  const [headerMediaHandle, setHeaderMediaHandle] = useState(""); // resumable handle for template review
  const [headerMediaId, setHeaderMediaId] = useState("");         // Cloud API media_id for sends
  const [headerMediaFileName, setHeaderMediaFileName] = useState("");
  const [headerMediaUploadState, setHeaderMediaUploadState] = useState({
    loading: false,
    error: "",
  });
  // For "order_product" mode: the auto-picked sample (used as Meta's review
  // example). Merchant can override by editing it like a URL.
  const [productSamples, setProductSamples] = useState([]);
  const [productSamplesState, setProductSamplesState] = useState({
    loading: false,
    error: "",
    loaded: false,
  });

  const handleHeaderMediaUpload = async (file) => {
    if (!file) return;
    setHeaderMediaUploadState({ loading: true, error: "" });
    setHeaderMediaHandle("");
    setHeaderMediaId("");
    setHeaderMediaFileName(file.name);
    try {
      const form = new FormData();
      form.append("file", file);
      // Media ids are per-number; upload under the same number the template is
      // being created on.
      if (accountId) form.append("account_id", accountId);
      // Raw fetch + manual session token: our axios interceptor would mangle
      // FormData via decamelizeKeys, so bypass it for this single endpoint.
      const token = await window.shopify?.idToken?.();
      const resp = await fetch(
        `https://${process.env.APP_HOST}/api/whatsapp/media_uploads`,
        {
          method: "POST",
          headers: token ? { Authorization: `Bearer ${token}` } : {},
          body: form,
        }
      );
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(data?.error || `Upload failed (${resp.status})`);
      setHeaderMediaHandle(data.handle || "");
      setHeaderMediaId(data.media_id || data.mediaId || "");
      setHeaderMediaUploadState({ loading: false, error: "" });
    } catch (err) {
      setHeaderMediaUploadState({
        loading: false,
        error: err?.message || "Upload failed",
      });
    }
  };

  const [body, setBody] = useState("");
  const [footer, setFooter] = useState("");

  const [buttons, setButtons] = useState([]);

  const [submitState, setSubmitState] = useState({
    loading: false,
    error: "",
    success: "",
  });
  // Anchor we scroll to so the merchant lands on the success/error banner
  // after a submit — without this, big templates keep the result off-screen.
  const topAnchorRef = useRef(null);
  const scrollToResult = () => {
    requestAnimationFrame(() => {
      topAnchorRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  };
  const [{ data: accountData }, refetchAccount] = useApi(
    { url: "/api/whatsapp/account", method: "GET" },
    { manual: false }
  );
  // Which number the template is created under (its WABA). Empty = default.
  const [accountId, setAccountId] = useState("");
  const [{ data: accountsData }] = useApi(
    { url: "/api/whatsapp/accounts", method: "GET" },
    { manual: false }
  );
  const accounts = accountsData?.accounts || [];
  useEffect(() => {
    if (!accountId && accounts.length) {
      const def = accounts.find((a) => a.isDefault) || accounts[0];
      if (def) setAccountId(String(def.id));
    }
  }, [accounts, accountId]);
  const [{ data: eventsData }] = useApi(
    { url: "/api/whatsapp/events", method: "GET" },
    { manual: false }
  );
  const [, createTemplateApi] = useApi(
    { url: "/api/whatsapp/templates", method: "POST" },
    { manual: true }
  );
  const [, fetchSampleProductImagesApi] = useApi(
    { url: "/api/whatsapp/sample_product_images", method: "GET" },
    { manual: true }
  );

  const accountConnected = accountData?.connected;
  const accountReady = accountConnected && accountData?.status === "verified";
  const credentialsMissing = !accountReady;

  // AUTHENTICATION events (e.g. OTP) are hidden from this free-form builder —
  // they have a fixed WhatsApp-managed shape and are submitted from the
  // library instead. Campaign broadcasts ARE listed: merchants create the
  // MARKETING template here, then pick it and map audience fields to its
  // variables in the Campaigns flow.
  const events = (eventsData?.events || []).filter(
    (e) => (e.templateCategory || "").toUpperCase() !== "AUTHENTICATION"
  );
  const selectedEvent = events.find((e) => e.key === eventTypeKey) || null;
  const eventVariables = selectedEvent?.variables || [];

  // When event changes, lock category to what the event requires.
  useEffect(() => {
    if (selectedEvent?.templateCategory) {
      setCategory(selectedEvent.templateCategory);
    }
  }, [selectedEvent?.templateCategory]);

  // Some events REQUIRE specific quick-reply buttons (e.g. COD verification needs
  // Confirm/Cancel — the send maps payloads cod_confirm/cod_cancel by position).
  // Pre-seed them so the merchant doesn't have to add them by hand. Only seeds
  // when no buttons exist yet, so it never clobbers the merchant's edits.
  useEffect(() => {
    const required = selectedEvent?.requiredQuickReplyPayloads || [];
    if (required.length === 0) return;
    setButtons((prev) => {
      if (prev.length > 0) return prev;
      return required.map((payload, i) => ({
        id: Date.now() + i,
        type: "quick_reply",
        // cod_confirm -> "Confirm", cod_cancel -> "Cancel"
        text: payload.split("_").pop().replace(/^./, (c) => c.toUpperCase()),
        url: "",
        urlMode: "static",
        urlVariable: "",
        urlBase: "",
        // Required by the event — the merchant may edit the text, but can't
        // delete it or change its type (the send maps payloads by position).
        required: true,
      }));
    });
  }, [selectedEvent?.key]);

  const eventOptions = [
    { label: events.length ? "Select an event…" : "Loading events…", value: "" },
    ...events.map((e) => ({ label: `${e.label} (${e.templateCategory})`, value: e.key })),
  ];

  const handleAddLanguage = (val) => {
    if (!val) return;
    if (!languages.includes(val)) setLanguages([...languages, val]);
    setShowLangPicker(false);
  };

  const handleRemoveLanguage = (val) => () => {
    setLanguages(languages.filter((l) => l !== val));
  };

  // Insert a variable into the chosen target. Records the position → variable.key mapping
  // and pre-fills the sample so Meta accepts the template on first try.
  const handleInsertVariable = (target, variable) => {
    if (!variable) return;
    const setter = target === "body" ? setBody : target === "footer" ? setFooter : setHeaderText;
    const current = target === "body" ? body : target === "footer" ? footer : headerText;
    const matches = (current || "").match(/\{\{\d+\}\}/g) || [];
    const position = String(matches.length + 1);
    setter((current || "") + `{{${position}}}`);
    setVariableMapping((prev) => ({ ...prev, [position]: variable.key }));
    if (target === "body") {
      setBodyExamples((prev) => ({ ...prev, [position]: variable.sample || prev[position] || "" }));
    } else if (target === "header") {
      setHeaderExamples((prev) => ({ ...prev, [position]: variable.sample || prev[position] || "" }));
    }
  };

  const wrapSelection = (target) => (wrapper) => {
    const setter = target === "body" ? setBody : target === "footer" ? setFooter : setHeaderText;
    const current = target === "body" ? body : target === "footer" ? footer : headerText;
    setter((current || "") + `${wrapper}text${wrapper}`);
  };

  const handleAddButton = () => {
    if (buttons.length >= 3) return;
    setButtons([
      ...buttons,
      {
        id: Date.now(),
        type: "quick_reply",
        text: "",
        url: "",
        urlMode: "static",
        urlVariable: "",
        urlBase: "",
      },
    ]);
  };

  const handleUpdateButton = (id, key, value) => {
    setButtons(buttons.map((b) => (b.id === id ? { ...b, [key]: value } : b)));
  };

  const handleRemoveButton = (id) => () => {
    setButtons(buttons.filter((b) => b.id !== id));
  };

  const bodyVars = useMemo(() => extractVariables(body), [body]);
  const headerVars = useMemo(
    () => (headerType === "text" ? extractVariables(headerText) : []),
    [headerType, headerText]
  );

  const previewBody = useMemo(() => {
    return (body || "Your message body will appear here.")
      .split("\n")
      .map((line, i) => (
        <div
          key={i}
          dangerouslySetInnerHTML={{
            __html: formatPreviewLine(line, bodyExamples) || "&nbsp;",
          }}
        />
      ));
  }, [body, bodyExamples]);

  const previewHeader = useMemo(() => {
    if (headerType === "none") return null;
    if (headerType === "text") {
      return (
        <div
          style={{ fontWeight: 700, marginBottom: 6 }}
          dangerouslySetInnerHTML={{
            __html: formatPreviewLine(headerText || "Header text", headerExamples),
          }}
        />
      );
    }
    const label = headerType.charAt(0).toUpperCase() + headerType.slice(1);
    return (
      <div
        style={{
          background: "#e7eef5",
          color: "#445870",
          borderRadius: 6,
          padding: "24px 12px",
          textAlign: "center",
          fontSize: 12,
          marginBottom: 8,
        }}
      >
        {I18n.t("whatsapp_template_create_tab.label_preview", { label: label })}
      </div>
    );
  }, [headerType, headerText]);

  const handleReset = () => {
    setName("");
    setEventTypeKey("");
    setVariableMapping({});
    setBodyExamples({});
    setHeaderExamples({});
    setLanguages(["en_US"]);
    setHeaderType("none");
    setHeaderText("");
    setHeaderMediaSource("url");
    setHeaderMediaUrl("");
    setHeaderMediaHandle("");
    setHeaderMediaId("");
    setHeaderMediaFileName("");
    setHeaderMediaUploadState({ loading: false, error: "" });
    setBody("");
    setFooter("");
    setButtons([]);
    setSubmitState({ loading: false, error: "", success: "" });
  };

  const handleCreate = async () => {
    if (credentialsMissing) {
      setSubmitState({
        loading: false,
        error: "Connect a WhatsApp account in the WhatsApp Accounts tab first.",
        success: "",
      });
      return;
    }
    if (!name || !body) return;
    if (!eventTypeKey) {
      setSubmitState({
        loading: false,
        error: "Select an event type before submitting.",
        success: "",
      });
      return;
    }

    setSubmitState({ loading: true, error: "", success: "" });

    const urlButton = buildUrlButtonPayload(buttons);

    // Build the structured header_media blob the backend persists for sends:
    // - For upload: include both the resumable HANDLE (for template review)
    //   and the Cloud API MEDIA_ID (for sends).
    // - For URL: just the URL.
    // - For order_product: store the dynamic mode plus an example_url to fall
    //   back on if the live payload can't yield a product image.
    let headerMedia = null;
    if (["image", "video", "document"].includes(headerType)) {
      const format = headerType.toUpperCase();
      if (headerMediaSource === "upload" && headerMediaHandle) {
        headerMedia = {
          format,
          handle: headerMediaHandle,
          media_id: headerMediaId || null,
        };
      } else if (headerMediaSource === "url" && headerMediaUrl) {
        headerMedia = { format, url: headerMediaUrl };
      } else if (headerMediaSource === "order_product" && headerMediaUrl) {
        headerMedia = {
          format,
          mode: "order_product_image",
          example_url: headerMediaUrl,
        };
      }
    }

    const payload = {
      name: name.trim().toLowerCase().replace(/\s+/g, "_"),
      language: languages[0] || "en_US",
      category,
      event_type_key: eventTypeKey,
      ...(accountId ? { account_id: Number(accountId) } : {}),
      variable_mapping: variableMapping,
      components: buildComponentsPayload({
        headerType,
        headerText,
        headerMediaUrl:
          headerMediaSource === "upload" ? headerMediaHandle : headerMediaUrl,
        body,
        footer,
        buttons,
        bodyExamples,
        headerExamples,
      }),
      ...(urlButton ? { url_button: urlButton } : {}),
      ...(headerMedia ? { header_media: headerMedia } : {}),
    };

    try {
      const { data } = await createTemplateApi({ data: payload });
      const t = data?.template || {};
      setSubmitState({
        loading: false,
        error: "",
        success: `Submitted '${t.name || payload.name}' — status: ${t.status || "pending"}${
          t.metaTemplateId ? ` (id: ${t.metaTemplateId})` : ""
        }`,
      });
      scrollToResult();
      // Tell any mounted templates list (e.g. in the sibling tab) to re-sync.
      window.dispatchEvent(new Event("whatsapp:template-created"));
    } catch (err) {
      setSubmitState({
        loading: false,
        error:
          err?.response?.data?.error ||
          err?.message ||
          "Failed to submit template.",
        success: "",
      });
      scrollToResult();
    }
  };

  const langOptionsForPicker = LANGUAGE_OPTIONS.filter(
    (l) => !languages.includes(l.value),
  );

  return (
    <Box paddingBlockStart="400">
      <div ref={topAnchorRef} />
      <BlockStack gap="400">
        {credentialsMissing && (
          <Banner tone="warning" title={I18n.t("whatsapp_template_create_tab.no_whatsapp_account_connected")}>
            <p>
              {accountConnected
                ? "Your WhatsApp account is connected but not yet verified. Finish verification in the WhatsApp Accounts tab to create and list templates."
                : "Go to the WhatsApp Accounts tab and connect your WhatsApp Business Account to create and list templates from your own WABA."}
            </p>
          </Banner>
        )}
        {submitState.error && (
          <Banner
            tone="critical"
            onDismiss={() => setSubmitState((s) => ({ ...s, error: "" }))}
          >
            {submitState.error}
          </Banner>
        )}
        {submitState.success && (
          <Banner
            tone="success"
            onDismiss={() => setSubmitState((s) => ({ ...s, success: "" }))}
          >
            {submitState.success}
          </Banner>
        )}

        <Layout>
          <Layout.Section>
            {/* One card per part of the template. As a single card this form
                ran to twenty-one fields; Built for Shopify allows five. */}
            <BlockStack gap="400">
            <Card>
              <BlockStack gap="400">
                <Text as="h2" variant="headingMd">
                  {I18n.t("whatsapp_template_create_tab.template_details")}
                </Text>

                {accounts.length > 1 && (
                  <Select
                    label={I18n.t("whatsapp_template_create_tab.create_under_number")}
                    helpText={I18n.t("whatsapp_template_create_tab.templates_belong_to_a_specific_whatsapp")}
                    options={accounts.map((a) => ({
                      label: `${a.displayLabel || a.displayPhoneNumber || "Number"}${a.isDefault ? " (default)" : ""}`,
                      value: String(a.id),
                    }))}
                    value={accountId}
                    onChange={setAccountId}
                  />
                )}

                <Select
                  label={I18n.t("whatsapp_template_create_tab.event_type")}
                  requiredIndicator
                  options={eventOptions}
                  value={eventTypeKey}
                  onChange={setEventTypeKey}
                  helpText={(() => {
                    if (!selectedEvent) {
                      return "Pick the Shopify event this template will be sent for. Variables you can use depend on the event.";
                    }
                    const bindable = selectedEvent.bindableCategories || [selectedEvent.templateCategory];
                    if (bindable.length > 1) {
                      return `${selectedEvent.description} Pick UTILITY or MARKETING — Meta auto-upgrades to MARKETING during review if the wording skews promotional.`;
                    }
                    return `${selectedEvent.description} Category is locked to ${selectedEvent.templateCategory} for this event.`;
                  })()}
                />

                <InlineStack gap="400" wrap={false} blockAlign="start">
                  <Box minWidth="0" width="100%">
                    <TextField
                      label={I18n.t("whatsapp_template_create_tab.name")}
                      requiredIndicator
                      value={name}
                      onChange={setName}
                      autoComplete="off"
                      placeholder={I18n.t("whatsapp_template_create_tab.e_g_order_confirmation")}
                      helpText={I18n.t("whatsapp_template_create_tab.will_be_lowercased_and_underscored_on")}
                    />
                  </Box>
                  <Box minWidth="0" width="100%">
                    {(() => {
                      // When an event allows multiple categories (e.g. abandoned_cart
                      // accepts UTILITY or MARKETING), let the merchant pick. Otherwise
                      // lock to the event's single allowed category.
                      const bindable = selectedEvent?.bindableCategories ||
                        (selectedEvent?.templateCategory ? [selectedEvent.templateCategory] : null);
                      const isMultiCategory = bindable && bindable.length > 1;
                      const options = bindable
                        ? CATEGORY_OPTIONS.filter((o) => bindable.includes(o.value))
                        : CATEGORY_OPTIONS;
                      const locked = !!selectedEvent && !isMultiCategory;
                      return (
                        <Select
                          label={I18n.t("whatsapp_template_create_tab.category")}
                          options={options}
                          value={category}
                          onChange={setCategory}
                          disabled={locked}
                          helpText={
                            locked
                              ? "Locked by the selected event type."
                              : isMultiCategory
                              ? "Pick the category that best matches your wording. Meta may upgrade UTILITY → MARKETING during review."
                              : undefined
                          }
                        />
                      );
                    })()}
                  </Box>
                </InlineStack>
              </BlockStack>
            </Card>

            <Card>
              <BlockStack gap="400">
                <BlockStack gap="200">
                  <Text as="h3" variant="headingSm">
                    {I18n.t("whatsapp_template_create_tab.languages")}
                  </Text>
                  <Text tone="subdued" as="p" variant="bodySm">
                    {I18n.t("whatsapp_template_create_tab.meta_creates_one_template_per_language")}
                  </Text>
                  <InlineStack gap="200" wrap>
                    {languages.map((l) => (
                      <Tag
                        key={l}
                        onRemove={
                          languages.length > 1
                            ? handleRemoveLanguage(l)
                            : undefined
                        }
                      >
                        {l}
                      </Tag>
                    ))}
                    {showLangPicker ? (
                      <Box minWidth="180px">
                        <Select
                          label=""
                          labelHidden
                          options={[
                            { label: I18n.t("whatsapp_template_create_tab.select_language"), value: "" },
                            ...langOptionsForPicker,
                          ]}
                          onChange={handleAddLanguage}
                          value=""
                        />
                      </Box>
                    ) : (
                      langOptionsForPicker.length > 0 && (
                        <Button
                          icon={PlusMinor}
                          variant="tertiary"
                          onClick={() => setShowLangPicker(true)}
                          accessibilityLabel={I18n.t("whatsapp_template_create_tab.add_language")}
                        />
                      )
                    )}
                  </InlineStack>
                </BlockStack>

              </BlockStack>
            </Card>

            <Card>
              <BlockStack gap="400">
                <BlockStack gap="200">
                  <Text as="h3" variant="headingSm">
                    {I18n.t("whatsapp_template_create_tab.header")}{" "}
                    <Text as="span" tone="subdued">
                      {I18n.t("whatsapp_template_create_tab.optional")}
                    </Text>
                  </Text>
                  <Text tone="subdued" as="p">
                    {I18n.t("whatsapp_template_create_tab.add_a_title_or_choose_which")}
                  </Text>
                  <Box maxWidth="280px">
                    <Select
                      label=""
                      labelHidden
                      options={HEADER_TYPE_OPTIONS}
                      value={headerType}
                      onChange={setHeaderType}
                    />
                  </Box>
                  {headerType === "text" && (
                    <>
                      <TextField
                        label=""
                        labelHidden
                        value={headerText}
                        onChange={setHeaderText}
                        maxLength={MAX_HEADER_LENGTH}
                        showCharacterCount
                        autoComplete="off"
                        placeholder={I18n.t("whatsapp_template_create_tab.enter_header_text")}
                      />
                      <VariableSamples
                        label={I18n.t("whatsapp_template_create_tab.sample_values_for_header_variables")}
                        vars={headerVars}
                        values={headerExamples}
                        onChange={setHeaderExamples}
                      />
                    </>
                  )}
                  {["image", "video", "document"].includes(headerType) && (
                    <BlockStack gap="200">
                      <Select
                        label={I18n.t("whatsapp_template_create_tab.sample_source")}
                        options={(() => {
                          const opts = [
                            { label: I18n.t("whatsapp_template_create_tab.paste_a_public_url"), value: "url" },
                            { label: I18n.t("whatsapp_template_create_tab.upload_a_file"), value: "upload" },
                          ];
                          // Dynamic order-product image only makes sense for
                          // IMAGE headers on order/checkout-driven events.
                          if (
                            headerType === "image" &&
                            ORDER_PRODUCT_IMAGE_EVENTS.includes(eventTypeKey)
                          ) {
                            opts.push({
                              label: I18n.t("whatsapp_template_create_tab.use_the_order_s_product_image"),
                              value: "order_product",
                            });
                          }
                          return opts;
                        })()}
                        value={headerMediaSource}
                        onChange={async (val) => {
                          setHeaderMediaSource(val);
                          // Auto-fetch a sample product image the first time
                          // the merchant switches to dynamic mode — Meta still
                          // needs a concrete example image for review.
                          if (
                            val === "order_product" &&
                            !productSamplesState.loaded &&
                            !productSamplesState.loading
                          ) {
                            setProductSamplesState({ loading: true, error: "", loaded: false });
                            try {
                              const { data } = await fetchSampleProductImagesApi();
                              const imgs = Array.isArray(data?.images) ? data.images : [];
                              setProductSamples(imgs);
                              if (imgs[0]?.url && !headerMediaUrl) {
                                setHeaderMediaUrl(imgs[0].url);
                              }
                              setProductSamplesState({
                                loading: false,
                                error: data?.error || "",
                                loaded: true,
                              });
                            } catch (err) {
                              setProductSamplesState({
                                loading: false,
                                error:
                                  err?.response?.data?.error ||
                                  err?.message ||
                                  "Could not fetch a sample image.",
                                loaded: true,
                              });
                            }
                          }
                        }}
                        helpText={
                          headerMediaSource === "upload"
                            ? "We upload to Meta via the Resumable Upload API and store the returned handle. Most reliable for strict accounts."
                            : headerMediaSource === "order_product"
                            ? "At send time we'll use the first product image from each order. The sample below is just for Meta's template review."
                            : "Meta may reject strict accounts on raw URLs. Switch to Upload if submission fails."
                        }
                      />

                      {headerMediaSource === "url" && (
                        <TextField
                          label={`Sample ${headerType} URL`}
                          value={headerMediaUrl}
                          onChange={setHeaderMediaUrl}
                          autoComplete="off"
                          placeholder={
                            headerType === "image"
                              ? "https://cdn.example.com/sample.jpg"
                              : headerType === "video"
                              ? "https://cdn.example.com/sample.mp4"
                              : "https://cdn.example.com/sample.pdf"
                          }
                        />
                      )}

                      {headerMediaSource === "order_product" && (
                        <BlockStack gap="200">
                          {productSamplesState.loading && (
                            <Text as="span" tone="subdued" variant="bodySm">
                              {I18n.t("whatsapp_template_create_tab.picking_a_sample_image_from_your")}
                            </Text>
                          )}
                          {productSamplesState.error && (
                            <Banner tone="warning">
                              {I18n.t("whatsapp_template_create_tab.sample_error_paste_url", {
                                error: productSamplesState.error,
                              })}
                            </Banner>
                          )}
                          <TextField
                            label={I18n.t("whatsapp_template_create_tab.review_sample_image_url")}
                            value={headerMediaUrl}
                            onChange={setHeaderMediaUrl}
                            autoComplete="off"
                            helpText={I18n.t("whatsapp_template_create_tab.auto_filled_from_one_of_your")}
                          />
                          {headerMediaUrl && (
                            <Box
                              padding="200"
                              borderColor="border"
                              borderWidth="025"
                              borderRadius="200"
                              background="bg-surface-secondary"
                            >
                              <img
                                src={headerMediaUrl}
                                alt={I18n.t("whatsapp_template_create_tab.sample_product")}
                                style={{ maxWidth: "100%", maxHeight: 120, objectFit: "contain" }}
                              />
                            </Box>
                          )}
                          {productSamples.length > 1 && (
                            <Select
                              label={I18n.t("whatsapp_template_create_tab.switch_sample")}
                              options={[
                                { label: I18n.t("whatsapp_template_create_tab.pick_another_product"), value: "" },
                                ...productSamples.map((s) => ({
                                  label: s.product_title || "Product",
                                  value: s.url,
                                })),
                              ]}
                              value=""
                              onChange={(v) => v && setHeaderMediaUrl(v)}
                            />
                          )}
                        </BlockStack>
                      )}

                      {headerMediaSource === "upload" && (
                        <BlockStack gap="200">
                          <input
                            type="file"
                            accept={
                              headerType === "image"
                                ? "image/*"
                                : headerType === "video"
                                ? "video/*"
                                : "application/pdf"
                            }
                            onChange={(e) =>
                              handleHeaderMediaUpload(e.target.files?.[0])
                            }
                            disabled={headerMediaUploadState.loading}
                          />
                          {headerMediaUploadState.loading && (
                            <Text as="span" tone="subdued" variant="bodySm">
                              {I18n.t("whatsapp_template_create_tab.uploading_file", {
                                file: headerMediaFileName,
                              })}
                            </Text>
                          )}
                          {headerMediaHandle && !headerMediaUploadState.loading && (
                            <Banner tone="success">
                              {I18n.t("whatsapp_template_create_tab.uploaded_file", {
                                file: headerMediaFileName,
                              })}
                            </Banner>
                          )}
                          {headerMediaUploadState.error && (
                            <Banner tone="critical">
                              {headerMediaUploadState.error}
                            </Banner>
                          )}
                        </BlockStack>
                      )}
                    </BlockStack>
                  )}
                </BlockStack>

              </BlockStack>
            </Card>

            <Card>
              <BlockStack gap="400">
                <BlockStack gap="200">
                  <Text as="h3" variant="headingSm">
                    {I18n.t("whatsapp_template_create_tab.body")}
                  </Text>
                  <Text tone="subdued" as="p">
                    {I18n.t("whatsapp_template_create_tab.enter_the_text_for_your_message")}
                  </Text>
                  <Box
                    padding="200"
                    borderColor="border"
                    borderWidth="025"
                    borderRadius="200"
                    background="bg-surface-secondary"
                  >
                    <InlineStack gap="200" blockAlign="center">
                      <Button
                        variant="tertiary"
                        accessibilityLabel={I18n.t("whatsapp_template_create_tab.emoji")}
                        onClick={() => setBody((body || "") + "😀")}
                      >
                        😀
                      </Button>
                      <Button
                        variant="tertiary"
                        accessibilityLabel={I18n.t("whatsapp_template_create_tab.bold")}
                        onClick={() => wrapSelection("body")("*")}
                      >
                        <strong>B</strong>
                      </Button>
                      <Button
                        variant="tertiary"
                        accessibilityLabel={I18n.t("whatsapp_template_create_tab.italic")}
                        onClick={() => wrapSelection("body")("_")}
                      >
                        <em>I</em>
                      </Button>
                      <Button
                        variant="tertiary"
                        accessibilityLabel={I18n.t("whatsapp_template_create_tab.strikethrough")}
                        onClick={() => wrapSelection("body")("~")}
                      >
                        <s>S</s>
                      </Button>
                      <Button
                        variant="tertiary"
                        accessibilityLabel={I18n.t("whatsapp_template_create_tab.monospace")}
                        onClick={() => wrapSelection("body")("```")}
                      >
                        {"<>"}
                      </Button>
                      <VariablePicker
                        target="body"
                        variables={eventVariables}
                        disabled={!selectedEvent}
                        onPick={(v) => handleInsertVariable("body", v)}
                      />
                    </InlineStack>
                  </Box>
                  <TextField
                    label=""
                    labelHidden
                    multiline={6}
                    value={body}
                    onChange={setBody}
                    maxLength={MAX_BODY_LENGTH}
                    showCharacterCount
                    autoComplete="off"
                    placeholder={I18n.t("whatsapp_template_create_tab.enter_text_in_english")}
                  />
                  <VariableSamples
                    label={I18n.t("whatsapp_template_create_tab.sample_values_for_body_variables")}
                    vars={bodyVars}
                    values={bodyExamples}
                    onChange={setBodyExamples}
                  />
                </BlockStack>

              </BlockStack>
            </Card>

            <Card>
              <BlockStack gap="400">
                <BlockStack gap="200">
                  <Text as="h3" variant="headingSm">
                    {I18n.t("whatsapp_template_create_tab.footer")}{" "}
                    <Text as="span" tone="subdued">
                      {I18n.t("whatsapp_template_create_tab.optional")}
                    </Text>
                  </Text>
                  <Text tone="subdued" as="p">
                    {I18n.t("whatsapp_template_create_tab.add_a_short_line_of_text")}
                  </Text>
                  <TextField
                    label=""
                    labelHidden
                    value={footer}
                    onChange={setFooter}
                    maxLength={MAX_FOOTER_LENGTH}
                    showCharacterCount
                    autoComplete="off"
                    placeholder={I18n.t("whatsapp_template_create_tab.enter_text_in_english")}
                  />
                </BlockStack>

              </BlockStack>
            </Card>

            <Card>
              <BlockStack gap="400">
                <BlockStack gap="200">
                  <Text as="h3" variant="headingSm">
                    {I18n.t("whatsapp_template_create_tab.button")}{" "}
                    <Text as="span" tone="subdued">
                      {I18n.t("whatsapp_template_create_tab.optional")}
                    </Text>
                  </Text>
                  <Text tone="subdued" as="p">
                    {I18n.t("whatsapp_template_create_tab.create_buttons_that_let_customers_respond")}
                  </Text>
                  {buttons.map((btn) => (
                    <Box
                      key={btn.id}
                      padding="300"
                      borderColor="border"
                      borderWidth="025"
                      borderRadius="200"
                    >
                      <BlockStack gap="200">
                        <InlineStack gap="200" align="space-between" blockAlign="center">
                          <Box minWidth="180px">
                            <Select
                              label={I18n.t("whatsapp_template_create_tab.type")}
                              options={[
                                { label: I18n.t("whatsapp_template_create_tab.quick_reply"), value: "quick_reply" },
                                { label: I18n.t("whatsapp_template_create_tab.url"), value: "url" },
                                { label: I18n.t("whatsapp_template_create_tab.phone_number"), value: "phone_number" },
                              ]}
                              value={btn.type}
                              onChange={(v) => handleUpdateButton(btn.id, "type", v)}
                              disabled={btn.required}
                            />
                          </Box>
                          {btn.required ? (
                            <Text variant="bodySm" tone="subdued">
                              {I18n.t("whatsapp_template_create_tab.required")}
                            </Text>
                          ) : (
                            <Button
                              icon={DeleteMinor}
                              variant="tertiary"
                              tone="critical"
                              accessibilityLabel={I18n.t("whatsapp_template_create_tab.remove_button")}
                              onClick={handleRemoveButton(btn.id)}
                            />
                          )}
                        </InlineStack>
                        <TextField
                          label={I18n.t("whatsapp_template_create_tab.button_text")}
                          value={btn.text}
                          onChange={(v) => handleUpdateButton(btn.id, "text", v)}
                          maxLength={25}
                          showCharacterCount
                          autoComplete="off"
                        />
                        {btn.type === "url" && (
                          <BlockStack gap="200">
                            <Select
                              label={I18n.t("whatsapp_template_create_tab.link_behaviour")}
                              options={[
                                { label: I18n.t("whatsapp_template_create_tab.static_url_same_for_everyone"), value: "static" },
                                {
                                  label: I18n.t("whatsapp_template_create_tab.use_a_known_link_from_the"),
                                  value: "predefined",
                                  disabled: !eventVariables.some((v) => v.kind === "url"),
                                },
                                {
                                  label: I18n.t("whatsapp_template_create_tab.build_with_a_base_url_variable"),
                                  value: "base",
                                  disabled: eventVariables.length === 0,
                                },
                              ]}
                              value={btn.urlMode || "static"}
                              onChange={(v) => handleUpdateButton(btn.id, "urlMode", v)}
                              helpText={
                                !eventTypeKey
                                  ? "Pick an event type above to enable dynamic link options."
                                  : btn.urlMode === "predefined"
                                  ? "The full link comes from the order/checkout payload. We shorten it with Cutt.ly at send time."
                                  : btn.urlMode === "base"
                                  ? "We append the chosen variable to your base URL, then shorten the result with Cutt.ly."
                                  : "Sent as-is. Same destination for every recipient."
                              }
                            />

                            {(!btn.urlMode || btn.urlMode === "static") && (
                              <TextField
                                label={I18n.t("whatsapp_template_create_tab.url")}
                                value={btn.url}
                                onChange={(v) => handleUpdateButton(btn.id, "url", v)}
                                autoComplete="off"
                                placeholder="https://example.com"
                              />
                            )}

                            {btn.urlMode === "predefined" && (
                              <Select
                                label={I18n.t("whatsapp_template_create_tab.link_variable")}
                                options={[
                                  { label: I18n.t("whatsapp_template_create_tab.select_a_link_variable"), value: "" },
                                  ...eventVariables
                                    .filter((v) => v.kind === "url")
                                    .map((v) => ({ label: v.label, value: v.key })),
                                ]}
                                value={btn.urlVariable || ""}
                                onChange={(v) => handleUpdateButton(btn.id, "urlVariable", v)}
                              />
                            )}

                            {btn.urlMode === "base" && (
                              <BlockStack gap="200">
                                <TextField
                                  label={I18n.t("whatsapp_template_create_tab.base_url")}
                                  value={btn.urlBase}
                                  onChange={(v) => handleUpdateButton(btn.id, "urlBase", v)}
                                  autoComplete="off"
                                  placeholder="https://shop.com/orders/"
                                  helpText={I18n.t("whatsapp_template_create_tab.must_start_with_https_and_have")}
                                />
                                <Select
                                  label={I18n.t("whatsapp_template_create_tab.suffix_variable")}
                                  options={[
                                    { label: I18n.t("whatsapp_template_create_tab.select_a_variable"), value: "" },
                                    ...eventVariables
                                      .filter((v) => v.kind !== "url")
                                      .map((v) => ({ label: v.label, value: v.key })),
                                  ]}
                                  value={btn.urlVariable || ""}
                                  onChange={(v) => handleUpdateButton(btn.id, "urlVariable", v)}
                                />
                              </BlockStack>
                            )}
                          </BlockStack>
                        )}
                        {btn.type === "phone_number" && (
                          <TextField
                            label={I18n.t("whatsapp_template_create_tab.phone_number")}
                            value={btn.url}
                            onChange={(v) => handleUpdateButton(btn.id, "url", v)}
                            autoComplete="off"
                            placeholder="+1 555 555 5555"
                          />
                        )}
                      </BlockStack>
                    </Box>
                  ))}
                  {buttons.length < 3 && (
                    <Box>
                      <Button onClick={handleAddButton} icon={PlusMinor} variant="primary">
                        {I18n.t("whatsapp_template_create_tab.add_button")}
                      </Button>
                    </Box>
                  )}
                </BlockStack>

              </BlockStack>
            </Card>

            <Card>
              <BlockStack gap="400">
                <InlineStack align="end" gap="200">
                  <Button onClick={handleReset} disabled={submitState.loading}>
                    {I18n.t("whatsapp_template_create_tab.reset")}
                  </Button>
                  <Button
                    variant="primary"
                    onClick={handleCreate}
                    disabled={!name || !body || submitState.loading || credentialsMissing}
                    loading={submitState.loading}
                  >
                    {I18n.t("whatsapp_template_create_tab.submit_to_whatsapp")}
                  </Button>
                </InlineStack>
              </BlockStack>
            </Card>
            </BlockStack>
          </Layout.Section>

          <Layout.Section variant="oneThird">
            <Card>
              <BlockStack gap="300">
                <Text as="h3" variant="headingMd">
                  {I18n.t("whatsapp_template_create_tab.preview")}
                </Text>
                <Box
                  padding="400"
                  borderRadius="300"
                  background="bg-surface-secondary"
                  minHeight="320px"
                >
                  <div
                    style={{
                      background: "#dcf8c6",
                      borderRadius: 10,
                      padding: 12,
                      maxWidth: 320,
                      marginLeft: "auto",
                      fontSize: 14,
                      color: "#111",
                      boxShadow: "0 1px 2px rgba(0,0,0,0.1)",
                      whiteSpace: "pre-wrap",
                      wordBreak: "break-word",
                    }}
                  >
                    {previewHeader}
                    <div style={{ lineHeight: 1.4 }}>{previewBody}</div>
                    {footer && (
                      <div
                        style={{
                          marginTop: 8,
                          fontSize: 12,
                          color: "#667781",
                        }}
                        dangerouslySetInnerHTML={{
                          __html: formatPreviewLine(footer),
                        }}
                      />
                    )}
                    <div
                      style={{
                        marginTop: 6,
                        fontSize: 10,
                        color: "#667781",
                        textAlign: "right",
                      }}
                    >
                      {I18n.t("whatsapp_template_create_tab.12_00_pm")}
                    </div>
                  </div>

                  {buttons.length > 0 && (
                    <div style={{ marginTop: 8, maxWidth: 320, marginLeft: "auto" }}>
                      {buttons.map((b) => (
                        <div
                          key={b.id}
                          style={{
                            background: "#fff",
                            borderRadius: 8,
                            padding: "8px 12px",
                            textAlign: "center",
                            fontSize: 13,
                            color: "#1f6feb",
                            marginTop: 4,
                            boxShadow: "0 1px 2px rgba(0,0,0,0.08)",
                          }}
                        >
                          {b.text || "Button"}
                        </div>
                      ))}
                    </div>
                  )}
                </Box>
                <Text as="p" tone="subdued" variant="bodySm">
                  {I18n.t("whatsapp_template_create_tab.category_summary", {
                    category:
                      CATEGORY_OPTIONS.find((c) => c.value === category)
                        ?.label ?? "",
                  })}
                  {languages.length > 0 &&
                    I18n.t("whatsapp_template_create_tab.languages_summary", {
                      languages: languages.join(", "),
                    })}
                </Text>
              </BlockStack>
            </Card>
          </Layout.Section>
        </Layout>

      </BlockStack>
    </Box>
  );
};

// Variable picker — replaces the old "Add Variable" button.
// Shows a dropdown of allow-listed variables for the chosen event; clicking one
// appends {{N}} to the field AND records the mapping (handled by parent).
const VariablePicker = ({ target: _target, variables, onPick, disabled }) => {
  const options = [
    { label: variables.length ? "Insert variable…" : "Select an event first", value: "" },
    ...variables.map((v) => ({ label: `${v.label} (${v.key})`, value: v.key })),
  ];

  return (
    <Box minWidth="200px">
      <Select
        label={I18n.t("whatsapp_template_create_tab.insert_variable")}
        labelHidden
        options={options}
        value=""
        disabled={disabled || !variables.length}
        onChange={(val) => {
          if (!val) return;
          const v = variables.find((x) => x.key === val);
          if (v) onPick(v);
        }}
      />
    </Box>
  );
};

const VariableSamples = ({ label, vars, values, onChange }) => {
  if (!vars || vars.length === 0) return null;
  const unique = Array.from(new Set(vars));
  return (
    <BlockStack gap="100">
      <Text as="p" tone="subdued" variant="bodySm">
        {I18n.t("whatsapp_template_create_tab.sample_values_help", {
          label: label,
        })}
      </Text>
      <InlineStack gap="200" wrap>
        {unique.map((key) => (
          <Box key={key} minWidth="180px">
            <TextField
              label={`{{${key}}}`}
              value={values[key] || ""}
              onChange={(val) => onChange({ ...values, [key]: val })}
              autoComplete="off"
              placeholder={placeholderForVariable(key)}
            />
          </Box>
        ))}
      </InlineStack>
    </BlockStack>
  );
};

export default WhatsappTemplateCreateTab;

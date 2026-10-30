import React, { useEffect, useMemo, useState } from "react";
import {
  Card,
  Box,
  BlockStack,
  InlineStack,
  Text,
  Badge,
  Banner,
  Button,
  Modal,
  TextField,
  Select,
  Spinner,
  EmptyState,
  Divider,
} from "@shopify/polaris";
import useApi from "../../Hooks/useApi";

import I18n from "../../i18n-lang";
const escapeHtml = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const fillExample = (text, examples) =>
  escapeHtml(text || "")
    .replace(/```([^`]+)```/g, "<code>$1</code>")
    .replace(/\*([^*\n]+)\*/g, "<strong>$1</strong>")
    .replace(/_([^_\n]+)_/g, "<em>$1</em>")
    .replace(/~([^~\n]+)~/g, "<s>$1</s>")
    .replace(/\{\{(\d+)\}\}/g, (_m, n) => {
      const sample = examples?.[Number(n) - 1];
      const display = (sample || `{{${n}}}`).toString();
      return `<span style="background:#fff3b0;padding:0 3px;border-radius:3px;">${escapeHtml(
        display
      )}</span>`;
    });

const findComponent = (components, type) =>
  (components || []).find((c) => (c?.type || "").toUpperCase() === type);

// Authentication templates have no merchant-authored body — WhatsApp renders a
// fixed string. Mirror that here so the preview reflects what the customer sees.
const authPreviewEntry = (entry) => {
  const body = findComponent(entry.components, "BODY");
  const footerComp = findComponent(entry.components, "FOOTER");
  const buttonsComp = findComponent(entry.components, "BUTTONS");
  const expiry = footerComp?.code_expiration_minutes || footerComp?.codeExpirationMinutes;
  const securityLine = body?.add_security_recommendation || body?.addSecurityRecommendation
    ? " For your security, do not share this code."
    : "";
  return {
    ...entry,
    components: [
      { type: "BODY", text: `{{1}} is your verification code.${securityLine}`, example: { body_text: [["123456"]] } },
      ...(expiry ? [{ type: "FOOTER", text: `This code expires in ${expiry} minutes.` }] : []),
      ...(buttonsComp ? [{ type: "BUTTONS", buttons: [{ type: "URL", text: (buttonsComp.buttons?.[0]?.text) || "Copy code" }] }] : []),
    ],
  };
};

const LibraryPreview = ({ entry: rawEntry }) => {
  const entry = isAuthEntry(rawEntry) ? authPreviewEntry(rawEntry) : rawEntry;
  const header = findComponent(entry.components, "HEADER");
  const body = findComponent(entry.components, "BODY");
  const footer = findComponent(entry.components, "FOOTER");
  const buttonsComp = findComponent(entry.components, "BUTTONS");
  const buttons = buttonsComp?.buttons || [];

  const bodyExample = body?.example?.body_text?.[0];

  return (
    <div
      style={{
        background: "#e5ddd5",
        borderRadius: 8,
        padding: 10,
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
          <div style={{ fontWeight: 700, marginBottom: 6 }}>{header.text}</div>
        )}
        {header && ["IMAGE", "VIDEO", "DOCUMENT"].includes(header.format) && (() => {
          // Library entries don't ship with a concrete media URL — they leave
          // the merchant to pick one in the Use modal. Show a placeholder
          // block so the preview makes it obvious there will be an image at
          // the top of the actual message.
          const sampleUrl = header?.example?.header_handle?.[0];
          if (sampleUrl && sampleUrl.startsWith("http")) {
            return (
              <img
                src={sampleUrl}
                alt={I18n.t("whatsapp_template_library.header")}
                style={{ width: "100%", maxHeight: 120, objectFit: "cover", borderRadius: 4, marginBottom: 6 }}
              />
            );
          }
          return (
            <div
              style={{
                background: "#d9d9d9",
                color: "#5e5e5e",
                fontSize: 11,
                textAlign: "center",
                padding: "26px 8px",
                borderRadius: 4,
                marginBottom: 6,
              }}
            >
              {header.format === "IMAGE" ? "🖼 Image header" : header.format === "VIDEO" ? "🎬 Video header" : "📄 Document header"}
            </div>
          );
        })()}
        {body && (
          <div>
            {(body.text || "").split("\n").map((line, i) => (
              <div
                key={i}
                dangerouslySetInnerHTML={{ __html: fillExample(line, bodyExample) || "&nbsp;" }}
              />
            ))}
          </div>
        )}
        {footer && (
          <div style={{ marginTop: 6, fontSize: 11, color: "#667781" }}>{footer.text}</div>
        )}
        <div style={{ fontSize: 10, color: "#8696a0", textAlign: "right", marginTop: 4 }}>
          {I18n.t("whatsapp_template_library.12_34_pm")}
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
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

// Extract distinct {{N}} positions from a string, sorted numerically.
const extractPositions = (text) => {
  if (!text) return [];
  const seen = new Set();
  (text.match(/\{\{(\d+)\}\}/g) || []).forEach((m) =>
    seen.add(m.replace(/[{}]/g, ""))
  );
  return Array.from(seen).sort((a, b) => Number(a) - Number(b));
};

// Build a fresh `components` array from edited body/header/footer text +
// existing non-text components (BUTTONS, IMAGE header, etc. survive untouched).
const isAuthEntry = (entry) =>
  (entry?.category || "").toUpperCase() === "AUTHENTICATION";

const buildComponentsFromEdit = (entry, { bodyText, footerText, headerText, mapping }) => {
  // Authentication templates have a fixed, WhatsApp-managed shape (no editable
  // body/footer text, a COPY_CODE button) — submit their components verbatim.
  if (isAuthEntry(entry)) return entry.components || [];
  return (entry.components || []).map((c) => {
    const type = (c?.type || "").toUpperCase();
    if (type === "BODY") {
      const positions = extractPositions(bodyText);
      const newBody = { type: "BODY", text: bodyText };
      if (positions.length) {
        // Re-derive the example array from samples so Meta accepts the new shape.
        newBody.example = {
          body_text: [positions.map((p) => `value_${p}`)],
        };
      }
      return newBody;
    }
    if (type === "FOOTER") return { type: "FOOTER", text: footerText };
    if (type === "HEADER" && (c?.format || "").toUpperCase() === "TEXT") {
      return { type: "HEADER", format: "TEXT", text: headerText };
    }
    return c;
  });
};

const VariableMappingList = ({ mapping, eventVars }) => {
  const entries = Object.entries(mapping || {}).sort(
    ([a], [b]) => Number(a) - Number(b)
  );
  if (entries.length === 0) return null;
  return (
    <BlockStack gap="050">
      {entries.map(([pos, varKey]) => {
        const v = eventVars.find((x) => x.key === varKey);
        return (
          <Text key={pos} as="span" tone="subdued" variant="bodySm">
            <span
              style={{
                background: "#fff3b0",
                padding: "0 4px",
                borderRadius: 3,
                fontFamily: "monospace",
              }}
            >
              {`{{${pos}}}`}
            </span>{" "}
            → {v ? v.label : varKey}
          </Text>
        );
      })}
    </BlockStack>
  );
};

// Events whose payload carries line-item product data we can pull an image
// from at send time. Mirrors the server-side gate in OrderProductImageResolver.
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

const SubmitModal = ({ entry, eventVars, onClose, onSubmitted }) => {
  const [name, setName] = useState(entry.nameSuggestion || entry.key);
  const isAuth = isAuthEntry(entry);

  const bodyComp = (entry.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "BODY"
  );
  const footerComp = (entry.components || []).find(
    (c) => (c?.type || "").toUpperCase() === "FOOTER"
  );
  const headerTextComp = (entry.components || []).find(
    (c) =>
      (c?.type || "").toUpperCase() === "HEADER" &&
      (c?.format || "").toUpperCase() === "TEXT"
  );
  // Library entries with an IMAGE/VIDEO/DOCUMENT header don't ship with a
  // concrete media URL — the merchant has to pick one here (URL, upload, or
  // dynamic product image). Without this, the template would be submitted
  // with no header.example.header_handle and Meta would reject it.
  const headerMediaComp = (entry.components || []).find(
    (c) =>
      (c?.type || "").toUpperCase() === "HEADER" &&
      ["IMAGE", "VIDEO", "DOCUMENT"].includes((c?.format || "").toUpperCase())
  );
  const headerMediaFormat = headerMediaComp?.format?.toUpperCase() || "";
  const headerMediaKind = headerMediaFormat.toLowerCase(); // 'image' | 'video' | 'document' | ''

  const [bodyText, setBodyText] = useState(bodyComp?.text || "");
  const [footerText, setFooterText] = useState(footerComp?.text || "");
  const [headerText, setHeaderText] = useState(headerTextComp?.text || "");
  const [mapping, setMapping] = useState(entry.variableMapping || {});

  // Header-media state. Only meaningful when headerMediaComp exists.
  // "url" | "upload" | "order_product"
  // Pre-made entries can declare an order-product-image header default
  // (entry.headerMedia.mode), e.g. the COD verification templates.
  const [headerMediaSource, setHeaderMediaSource] = useState(
    entry.headerMedia?.mode === "order_product_image" ? "order_product" : "url",
  );
  const [headerMediaUrl, setHeaderMediaUrl] = useState("");
  const [headerMediaHandle, setHeaderMediaHandle] = useState("");
  const [headerMediaId, setHeaderMediaId] = useState("");
  const [headerMediaFileName, setHeaderMediaFileName] = useState("");
  const [headerMediaUploadState, setHeaderMediaUploadState] = useState({
    loading: false,
    error: "",
  });
  const [productSamples, setProductSamples] = useState([]);
  const [productSamplesState, setProductSamplesState] = useState({
    loading: false,
    error: "",
    loaded: false,
  });

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const [, createTemplateApi] = useApi(
    { url: "/api/whatsapp/templates", method: "POST" },
    { manual: true }
  );
  const [, uploadMediaApi] = useApi(
    { url: "/api/whatsapp/media_uploads", method: "POST" },
    { manual: true }
  );
  const [, fetchSampleProductImagesApi] = useApi(
    { url: "/api/whatsapp/sample_product_images", method: "GET" },
    { manual: true }
  );

  const handleHeaderMediaUpload = async (file) => {
    if (!file) return;
    setHeaderMediaUploadState({ loading: true, error: "" });
    setHeaderMediaHandle("");
    setHeaderMediaId("");
    setHeaderMediaFileName(file.name);
    try {
      const fd = new FormData();
      fd.append("file", file);
      const { data } = await uploadMediaApi({ data: fd });
      setHeaderMediaHandle(data?.handle || "");
      setHeaderMediaId(data?.media_id || data?.mediaId || "");
      setHeaderMediaUploadState({ loading: false, error: "" });
    } catch (err) {
      setHeaderMediaUploadState({
        loading: false,
        error:
          err?.response?.data?.error ||
          err?.message ||
          "Upload failed",
      });
    }
  };

  const handleSourceChange = async (val) => {
    setHeaderMediaSource(val);
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
        if (imgs[0]?.url && !headerMediaUrl) setHeaderMediaUrl(imgs[0].url);
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
  };

  // If a pre-made entry defaults to an order-product-image header, fetch a
  // sample product image on mount so the Meta approval sample is populated.
  useEffect(() => {
    if (headerMediaComp && headerMediaSource === "order_product") {
      handleSourceChange("order_product");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // The set of positions we currently need to map is derived live from the
  // body text — if the merchant adds {{3}} or removes {{2}}, the picker list
  // updates with it.
  const positions = useMemo(() => extractPositions(bodyText), [bodyText]);

  // Drop any mapping entry whose position no longer appears in the body.
  // Keep keys that are still present.
  const effectiveMapping = useMemo(() => {
    const next = {};
    positions.forEach((p) => {
      if (mapping[p]) next[p] = mapping[p];
    });
    return next;
  }, [positions, mapping]);

  // Build a synthetic entry for the live preview so it reflects the edits.
  // Authentication templates aren't editable, so preview the entry as-is.
  const previewEntry = useMemo(() => {
    if (isAuth) return entry;
    const examples = {};
    positions.forEach((p) => {
      const v = eventVars.find((x) => x.key === effectiveMapping[p]);
      examples[p] = v?.sample || `value_${p}`;
    });
    const newComponents = (entry.components || []).map((c) => {
      const t = (c?.type || "").toUpperCase();
      if (t === "BODY")
        return {
          type: "BODY",
          text: bodyText,
          example: { body_text: [positions.map((p) => examples[p])] },
        };
      if (t === "FOOTER") return { type: "FOOTER", text: footerText };
      if (t === "HEADER" && (c?.format || "").toUpperCase() === "TEXT")
        return { type: "HEADER", format: "TEXT", text: headerText };
      // Media header — inject the chosen URL (URL mode or order_product mode)
      // so the inline preview reflects the picked image. Upload mode keeps the
      // placeholder; we don't have a public URL to display until Meta serves
      // the handle back, which only happens after approval.
      if (
        t === "HEADER" &&
        ["IMAGE", "VIDEO", "DOCUMENT"].includes((c?.format || "").toUpperCase())
      ) {
        const preview = { ...c };
        if ((headerMediaSource === "url" || headerMediaSource === "order_product") && headerMediaUrl) {
          preview.example = { header_handle: [headerMediaUrl] };
        }
        return preview;
      }
      return c;
    });
    return { ...entry, components: newComponents };
  }, [entry, bodyText, footerText, headerText, positions, effectiveMapping, eventVars, headerMediaSource, headerMediaUrl]);

  const handleSubmit = async () => {
    setSubmitting(true);
    setError("");
    try {
      // Validate the media-header picker before we hit Meta.
      if (headerMediaComp && !isAuth) {
        if (headerMediaSource === "upload" && !headerMediaHandle) {
          setSubmitting(false);
          setError(`Upload a ${headerMediaKind} sample for the header before submitting.`);
          return;
        }
        if ((headerMediaSource === "url" || headerMediaSource === "order_product") && !headerMediaUrl) {
          setSubmitting(false);
          setError(`Provide a ${headerMediaKind} URL for the header sample.`);
          return;
        }
      }

      let components = buildComponentsFromEdit(entry, {
        bodyText,
        footerText,
        headerText,
        mapping: effectiveMapping,
      });

      // Splice the chosen media sample into the HEADER's example.header_handle
      // so Meta's template-review can render it. The backend (Meta::TemplateService)
      // converts raw URLs to resumable handles before posting to Meta.
      if (headerMediaComp && !isAuth) {
        const sampleValue =
          headerMediaSource === "upload" ? headerMediaHandle : headerMediaUrl;
        components = components.map((c) => {
          const t = (c?.type || "").toUpperCase();
          if (
            t === "HEADER" &&
            ["IMAGE", "VIDEO", "DOCUMENT"].includes((c?.format || "").toUpperCase())
          ) {
            return { ...c, example: { header_handle: [sampleValue] } };
          }
          return c;
        });
      }

      let headerMedia;
      if (headerMediaComp && !isAuth) {
        if (headerMediaSource === "upload" && headerMediaHandle) {
          headerMedia = {
            format: headerMediaFormat,
            handle: headerMediaHandle,
            media_id: headerMediaId || null,
          };
        } else if (headerMediaSource === "url" && headerMediaUrl) {
          headerMedia = { format: headerMediaFormat, url: headerMediaUrl };
        } else if (headerMediaSource === "order_product" && headerMediaUrl) {
          headerMedia = {
            format: headerMediaFormat,
            mode: "order_product_image",
            example_url: headerMediaUrl,
          };
        }
      }

      const payload = {
        name: name.trim().toLowerCase().replace(/\s+/g, "_"),
        language: entry.language,
        category: entry.category,
        event_type_key: entry.eventTypeKey,
        components,
        variable_mapping: isAuth ? (entry.variableMapping || {}) : effectiveMapping,
        url_button: entry.urlButton || undefined,
        ...(headerMedia ? { header_media: headerMedia } : {}),
      };
      const { data } = await createTemplateApi({ data: payload });
      onSubmitted(data?.template);
      window.dispatchEvent(new Event("whatsapp:template-created"));
    } catch (err) {
      setError(err?.response?.data?.error || err?.message || "Submission failed");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Modal
      open
      onClose={onClose}
      title={`Use "${entry.title}"`}
      primaryAction={{
        content: I18n.t("whatsapp_template_library.submit_to_whatsapp"),
        onAction: handleSubmit,
        loading: submitting,
      }}
      secondaryActions={[{ content: I18n.t("whatsapp_template_library.cancel"), onAction: onClose }]}
      large
    >
      <Modal.Section>
        <BlockStack gap="400">
          {error && <Banner tone="critical">{error}</Banner>}

          <TextField
            label={I18n.t("whatsapp_template_library.template_name")}
            value={name}
            onChange={setName}
            helpText={I18n.t("whatsapp_template_library.will_be_lowercased_and_underscored_on")}
            autoComplete="off"
          />

          {isAuth && (
            <Banner tone="info">
              {I18n.t("whatsapp_template_library.this_is_a_whatsapp")} <strong>{I18n.t("whatsapp_template_library.authentication")}</strong> {I18n.t("whatsapp_template_library.template_the_message_wording_and_the")}
            </Banner>
          )}

          {!isAuth && headerTextComp && (
            <TextField
              label={I18n.t("whatsapp_template_library.header_text")}
              value={headerText}
              onChange={setHeaderText}
              autoComplete="off"
              maxLength={60}
              showCharacterCount
            />
          )}

          {!isAuth && headerMediaComp && (
            <BlockStack gap="200">
              <Text as="h3" variant="headingSm">
                {`Header ${headerMediaKind}`}
              </Text>
              <Text as="p" tone="subdued" variant="bodySm">
                {I18n.t("whatsapp_template_library.template_has_media_header", {
                  kind: headerMediaKind,
                })}
              </Text>
              <Select
                label={I18n.t("whatsapp_template_library.sample_source")}
                options={(() => {
                  const opts = [
                    { label: I18n.t("whatsapp_template_library.paste_a_public_url"), value: "url" },
                    { label: I18n.t("whatsapp_template_library.upload_a_file"), value: "upload" },
                  ];
                  if (
                    headerMediaFormat === "IMAGE" &&
                    ORDER_PRODUCT_IMAGE_EVENTS.includes(entry.eventTypeKey)
                  ) {
                    opts.push({
                      label: I18n.t("whatsapp_template_library.use_the_order_s_product_image"),
                      value: "order_product",
                    });
                  }
                  return opts;
                })()}
                value={headerMediaSource}
                onChange={handleSourceChange}
                helpText={
                  headerMediaSource === "upload"
                    ? "We upload to Meta and store the returned handle. Most reliable for strict accounts."
                    : headerMediaSource === "order_product"
                    ? "At send time we'll use the first product image from each order. The sample below is only for Meta's template review."
                    : "Meta may reject strict accounts on raw URLs. Switch to Upload if submission fails."
                }
              />

              {headerMediaSource === "url" && (
                <TextField
                  label={`Sample ${headerMediaKind} URL`}
                  value={headerMediaUrl}
                  onChange={setHeaderMediaUrl}
                  autoComplete="off"
                  placeholder={
                    headerMediaFormat === "IMAGE"
                      ? "https://cdn.example.com/sample.jpg"
                      : headerMediaFormat === "VIDEO"
                      ? "https://cdn.example.com/sample.mp4"
                      : "https://cdn.example.com/sample.pdf"
                  }
                />
              )}

              {headerMediaSource === "upload" && (
                <BlockStack gap="200">
                  <input
                    type="file"
                    accept={
                      headerMediaFormat === "IMAGE"
                        ? "image/*"
                        : headerMediaFormat === "VIDEO"
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
                      {I18n.t("whatsapp_template_library.uploading_file", {
                        file: headerMediaFileName,
                      })}
                    </Text>
                  )}
                  {headerMediaHandle && !headerMediaUploadState.loading && (
                    <Banner tone="success">
                      {I18n.t("whatsapp_template_library.uploaded_file", {
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

              {headerMediaSource === "order_product" && (
                <BlockStack gap="200">
                  {productSamplesState.loading && (
                    <Text as="span" tone="subdued" variant="bodySm">
                      {I18n.t("whatsapp_template_library.picking_a_sample_image_from_your")}
                    </Text>
                  )}
                  {productSamplesState.error && (
                    <Banner tone="warning">
                      {I18n.t("whatsapp_template_library.sample_error_paste_url", {
                        error: productSamplesState.error,
                      })}
                    </Banner>
                  )}
                  <TextField
                    label={I18n.t("whatsapp_template_library.review_sample_image_url")}
                    value={headerMediaUrl}
                    onChange={setHeaderMediaUrl}
                    autoComplete="off"
                    helpText={I18n.t("whatsapp_template_library.auto_filled_from_one_of_your")}
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
                        alt={I18n.t("whatsapp_template_library.sample_product")}
                        style={{ maxWidth: "100%", maxHeight: 120, objectFit: "contain" }}
                      />
                    </Box>
                  )}
                  {productSamples.length > 1 && (
                    <Select
                      label={I18n.t("whatsapp_template_library.switch_sample")}
                      options={[
                        { label: I18n.t("whatsapp_template_library.pick_another_product"), value: "" },
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
            </BlockStack>
          )}

          {!isAuth && (
            <TextField
              label={I18n.t("whatsapp_template_library.body")}
              value={bodyText}
              onChange={setBodyText}
              multiline={4}
              autoComplete="off"
              maxLength={1024}
              showCharacterCount
              helpText={I18n.t("whatsapp_template_library.use_for_variables_the_picker_below")}
            />
          )}

          {!isAuth && footerComp && (
            <TextField
              label={I18n.t("whatsapp_template_library.footer")}
              value={footerText}
              onChange={setFooterText}
              autoComplete="off"
              maxLength={60}
              showCharacterCount
            />
          )}

          {!isAuth && positions.length > 0 && (
            <>
              <Divider />
              <Text as="h3" variant="headingSm">
                {I18n.t("whatsapp_template_library.variables_count", {
                  count: positions.length,
                })}
              </Text>
              <Text as="p" tone="subdued" variant="bodySm">
                {I18n.t("whatsapp_template_library.pick_variable_per_slot")}
              </Text>
              {positions.map((p) => (
                <Select
                  key={p}
                  label={`{{${p}}}`}
                  options={[
                    { label: I18n.t("whatsapp_template_library.choose_a_variable"), value: "" },
                    ...eventVars.map((v) => ({ label: v.label, value: v.key })),
                  ]}
                  value={effectiveMapping[p] || ""}
                  onChange={(v) =>
                    setMapping((prev) => ({ ...prev, [p]: v }))
                  }
                />
              ))}
            </>
          )}

          <Divider />
          <Text as="h3" variant="headingSm">
            {I18n.t("whatsapp_template_library.live_preview")}
          </Text>
          <LibraryPreview entry={previewEntry} />
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

const WhatsappTemplateLibrary = () => {
  const [{ data, loading, error }] = useApi(
    { url: "/api/whatsapp/template_library", method: "GET" },
    { manual: false }
  );
  const [{ data: account }] = useApi(
    { url: "/api/whatsapp/account", method: "GET" },
    { manual: false }
  );
  const [{ data: eventsData }] = useApi(
    { url: "/api/whatsapp/events", method: "GET" },
    { manual: false }
  );
  const [submitting, setSubmitting] = useState(null);
  const [successBanner, setSuccessBanner] = useState("");

  const accountReady = account?.connected && account?.status === "verified";
  const entries = data?.entries || [];

  // event key → list of variables, used by the edit modal and the mapping
  // explainer beneath each card preview.
  const eventVarsByKey = useMemo(() => {
    const map = {};
    (eventsData?.events || []).forEach((e) => {
      map[e.key] = e.variables || [];
    });
    return map;
  }, [eventsData]);

  // Group by event for visual separation.
  const grouped = useMemo(() => {
    const map = new Map();
    entries.forEach((e) => {
      const key = e.eventTypeKey;
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(e);
    });
    return Array.from(map.entries());
  }, [entries]);

  if (!accountReady) {
    return (
      <Card>
        <Box padding="500">
          <EmptyState
            heading={I18n.t("whatsapp_template_library.connect_a_verified_whatsapp_account_first")}
            action={{ content: I18n.t("whatsapp_template_library.go_to_account"), url: "/features/whatsapp/account" }}
            image="https://cdn.shopify.com/s/files/1/0262/4071/2726/files/emptystate-files.png"
          >
            <Text as="p" tone="subdued">
              {I18n.t("whatsapp_template_library.once_your_account_is_verified_you")}
            </Text>
          </EmptyState>
        </Box>
      </Card>
    );
  }

  return (
    <BlockStack gap="400">
      <Banner tone="info">
        {I18n.t("whatsapp_template_library.pre_made_templates_curated_for_common")}
      </Banner>

      {successBanner && (
        <Banner tone="success" onDismiss={() => setSuccessBanner("")}>
          {successBanner}
        </Banner>
      )}

      {loading && (
        <Card>
          <Box padding="500">
            <InlineStack gap="200" align="center">
              <Spinner size="small" />
              <Text as="span">{I18n.t("whatsapp_template_library.loading_library")}</Text>
            </InlineStack>
          </Box>
        </Card>
      )}

      {error && <Banner tone="critical">{error.message || "Failed to load library."}</Banner>}

      {grouped.map(([eventKey, list]) => (
        <Card key={eventKey} padding="600">
            <BlockStack gap="300">
              <Text as="h2" variant="headingMd">
                {humanizeEvent(eventKey)}
              </Text>
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))",
                  gap: 16,
                }}
              >
                {list.map((entry) => (
                  <Box
                    key={entry.key}
                    padding="300"
                    borderColor="border"
                    borderWidth="025"
                    borderRadius="200"
                  >
                    <BlockStack gap="200">
                      <BlockStack gap="050">
                        <InlineStack gap="200" blockAlign="center" wrap>
                          <Text as="h3" variant="headingSm">
                            {entry.title}
                          </Text>
                          <Badge tone="info">{entry.category}</Badge>
                        </InlineStack>
                        <Text as="p" tone="subdued" variant="bodySm">
                          {entry.description}
                        </Text>
                      </BlockStack>
                      <LibraryPreview entry={entry} />
                      <VariableMappingList
                        mapping={entry.variableMapping}
                        eventVars={eventVarsByKey[entry.eventTypeKey] || []}
                      />
                      <InlineStack gap="200" wrap>
                        {(entry.tags || []).map((t) => (
                          <Badge key={t}>{t}</Badge>
                        ))}
                      </InlineStack>
                      <Button variant="primary" onClick={() => setSubmitting(entry)}>
                        {I18n.t("whatsapp_template_library.edit_use_this_template")}
                      </Button>
                    </BlockStack>
                  </Box>
                ))}
              </div>
            </BlockStack>
          
        </Card>
      ))}

      {submitting && (
        <SubmitModal
          entry={submitting}
          eventVars={eventVarsByKey[submitting.eventTypeKey] || []}
          onClose={() => setSubmitting(null)}
          onSubmitted={(t) => {
            setSubmitting(null);
            setSuccessBanner(
              `Submitted '${t?.name || submitting.nameSuggestion}'. Meta will review and notify you on approval.`
            );
          }}
        />
      )}
    </BlockStack>
  );
};

const humanizeEvent = (key) => {
  switch (key) {
    case "order_created":
      return "Order placed";
    case "order_fulfilled":
      return "Order shipped / fulfilled";
    case "abandoned_cart":
      return "Abandoned cart";
    case "first_time_purchase":
      return "First-time purchase";
    case "pre_order_otp":
      return "OTP message";
    case "campaign_broadcast":
      return "Marketing broadcast";
    case "cod_verification":
      return "COD verification";
    case "cod_verification_reminder":
      return "COD verification reminder";
    case "order_cancelled":
      return "Order cancelled";
    case "order_out_for_delivery":
      return "Out for delivery";
    case "order_delivered":
      return "Order delivered";
    case "feedback_request":
      return "Feedback request";
    case "reorder_reminder":
      return "Reorder reminder";
    default:
      return key;
  }
};

export default WhatsappTemplateLibrary;

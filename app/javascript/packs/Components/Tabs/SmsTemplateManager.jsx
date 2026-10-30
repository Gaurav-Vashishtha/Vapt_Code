import React, { useEffect, useMemo, useState } from "react";
import { Banner, BlockStack, Button, Card, DataTable, InlineStack, Select, Text, TextField } from "@shopify/polaris";
import { navigateTo } from "../../../utils/navigate";
import I18n from "../../i18n-lang";

const normalizeAllowedVariables = (value) => {
  if (Array.isArray(value)) return value.map((v) => String(v));
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) return parsed.map((v) => String(v));
    } catch (e) {
      return value
        .split(",")
        .map((v) => v.trim())
        .filter(Boolean);
    }
  }
  if (value && typeof value === "object") return Object.values(value).map((v) => String(v));
  return [];
};

const SmsTemplateManager = ({ shop, plan, initialTemplateKey }) => {
  const [types, setTypes] = useState([]);
  const [selectedKey, setSelectedKey] = useState("");
  const [body, setBody] = useState("");
  const [loading, setLoading] = useState(false);
  const [banner, setBanner] = useState(null);
  const [history, setHistory] = useState([]);
  const [eligibility, setEligibility] = useState({
    allowed: false,
    reason: "Template approvals are available on paid plans only",
  });

  const isEligibleForTemplates = useMemo(
    () => Boolean(eligibility?.allowed),
    [eligibility],
  );

  const selectedType = useMemo(
    () => types.find((t) => t.key === selectedKey),
    [types, selectedKey],
  );

  const loadTypes = async () => {
    setLoading(true);
    try {
      const res = await fetch(`https://${process.env.APP_HOST}/sms_template_approvals`);
      const json = await res.json();
      const payload = json.types || [];
      setTypes(payload);
      setHistory(json.history || []);
      setEligibility(
        json.eligibility || {
          allowed: false,
          reason: "Template approvals are available on paid plans only",
        },
      );
      if (payload.length > 0) {
        const first = payload[0];
        setSelectedKey(first.key);
        const firstBody = first.latest_approval?.status === "approved"
          ? first.latest_approval?.body
          : first.current_body;
        setBody(firstBody || "");
      }
    } catch (e) {
      setBanner({ tone: "critical", message: "Failed to load SMS template types." });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadTypes();
  }, []);

  useEffect(() => {
    if (!initialTemplateKey || types.length === 0) return;
    const match = types.find((t) => t.key === initialTemplateKey);
    if (match) setSelectedKey(initialTemplateKey);
  }, [initialTemplateKey, types]);

  useEffect(() => {
    if (selectedType) {
      const nextBody = selectedType.latest_approval?.status === "approved"
        ? selectedType.latest_approval?.body
        : selectedType.current_body;
      setBody(nextBody || "");
    }
  }, [selectedType?.key]);

  const typeOptions = types.map((t) => ({ label: t.display_name, value: t.key }));
  const variableMatches = body.match(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g) || [];
  const variableCount = variableMatches.length;
  const simulatedLength = body.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, "x".repeat(15)).length;
  const charsLeft = 160 - simulatedLength;
  const maxVarsAllowed = Math.min(selectedType?.max_variables || 3, 3);
  const isTemplateInvalid = variableCount > maxVarsAllowed || simulatedLength > 160;
  const hasPendingForType = selectedType?.latest_approval?.status === "pending";

  const submit = async () => {
    if (!selectedType) return;
    setLoading(true);
    setBanner(null);
    try {
      const res = await fetch(`https://${process.env.APP_HOST}/sms_template_approvals`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          template_type_key: selectedType.key,
          body,
        }),
      });
      const json = await res.json();
      if (!res.ok || !json.ok) {
        const errors = json.errors || ["Failed to submit template"];
        setBanner({ tone: "critical", message: errors.join(", ") });
      } else {
        setBanner({ tone: "success", message: "Template submitted for approval." });
        loadTypes();
      }
    } catch (e) {
      setBanner({ tone: "critical", message: "Failed to submit template." });
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      <BlockStack gap="300">
        <Text variant="headingMd" as="h3">
          {I18n.t("sms_template_manager.sms_template_management")}
        </Text>
        <Banner tone="info" title={I18n.t("sms_template_manager.how_it_works")}>
          {I18n.t("sms_template_manager.select_the_sms_notification_type_update")}
        </Banner>
        {!isEligibleForTemplates && (
          <Banner tone="warning" title={I18n.t("sms_template_manager.paid_plan_required")}>
            {eligibility?.reason ||
              "Upgrade to a paid plan to customize SMS templates and submit for approval."}
            <div style={{ marginTop: "8px" }}>
              <Button onClick={() => navigateTo("/subscription")}>
                {I18n.t("sms_template_manager.upgrade_now")}
              </Button>
            </div>
          </Banner>
        )}
        {banner && (
          <Banner tone={banner.tone} title={banner.message} />
        )}
        {typeOptions.length > 0 ? (
          <>
            <Select
              label={I18n.t("sms_template_manager.notification_type")}
              options={typeOptions}
              value={selectedKey}
              onChange={setSelectedKey}
            />
            {selectedType && (
              <InlineStack gap="200" wrap>
                <Text as="span" variant="bodySm" tone="subdued">
                  {I18n.t("sms_template_manager.allowed_vars", {
                    vars: normalizeAllowedVariables(
                      selectedType.allowed_variables
                    ).join(", "),
                  })}
                </Text>
                <Text as="span" variant="bodySm" tone="subdued">
                  {I18n.t("sms_template_manager.max_vars", {
                    count: Math.min(selectedType.max_variables || 3, 3),
                  })}
                </Text>
                <Text as="span" variant="bodySm" tone="subdued">
                  {I18n.t("sms_template_manager.status_value", {
                    status:
                      selectedType.latest_approval?.status ||
                      I18n.t("sms_template_manager.not_submitted"),
                  })}
                </Text>
                <Text as="span" variant="bodySm" tone="subdued">
                  {I18n.t("sms_template_manager.live_template", {
                    version:
                      selectedType.latest_approval?.status === "approved"
                        ? I18n.t("sms_template_manager.approved_version")
                        : I18n.t("sms_template_manager.current_settings_template"),
                  })}
                </Text>
              </InlineStack>
            )}
            <TextField
              label={I18n.t("sms_template_manager.template_body")}
              multiline={4}
              value={body}
              onChange={setBody}
              autoComplete="off"
              maxLength={160}
            />
            <Text as="p" variant="bodySm" tone={charsLeft < 0 ? "critical" : "subdued"}>
              {I18n.t("sms_template_manager.effective_length", {
                length: simulatedLength,
              })}
            </Text>
            <Text as="p" variant="bodySm" tone={variableCount > maxVarsAllowed ? "critical" : "subdued"}>
              {I18n.t("sms_template_manager.variables_used", {
                used: variableCount,
                max: maxVarsAllowed,
              })}
            </Text>
            <InlineStack>
              <Button
                variant="primary"
                loading={loading}
                disabled={!isEligibleForTemplates || !selectedType || isTemplateInvalid || hasPendingForType}
                onClick={submit}
              >
                {I18n.t("sms_template_manager.apply_for_approval")}
              </Button>
            </InlineStack>
            {hasPendingForType && (
              <Text as="p" variant="bodySm" tone="warning">
                {I18n.t("sms_template_manager.a_request_for_this_template_type")}
              </Text>
            )}
            <Text variant="headingSm" as="h4">
              {I18n.t("sms_template_manager.request_history")}
            </Text>
            <DataTable
              columnContentTypes={["text", "text", "text", "text", "text"]}
              headings={["Type", "Status", "Submitted", "Submitted body", "Review notes"]}
              rows={history.map((row) => [
                row.template_type_key,
                row.status,
                row.submitted_at ? new Date(row.submitted_at).toLocaleString() : "-",
                row.body || "-",
                row.review_reason || "-",
              ])}
            />
          </>
        ) : (
          <Text as="p" tone="subdued">
            {I18n.t("sms_template_manager.no_sms_template_types_configured")}
          </Text>
        )}
      </BlockStack>
    </Card>
  );
};

export default SmsTemplateManager;

import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  Page,
  Badge,
  Banner,
  BlockStack,
  Box,
  Button,
  Card,
  Checkbox,
  Collapsible,
  EmptyState,
  InlineStack,
  Select,
  Spinner,
  Text,
  TextField,
} from "@shopify/polaris";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";
import { navigateTo } from "../../../utils/navigate";

const SIGNATURE_SCHEMES = [
  { get label() {
      return I18n.t("webhook_endpoints.shared_secret_header");
    }, value: "shared_secret" },
  { get label() {
      return I18n.t("webhook_endpoints.hmac_sha_256_of_body");
    }, value: "hmac_sha256" },
  { get label() {
      return I18n.t("webhook_endpoints.no_verification");
    }, value: "none" },
];

const STATUS_TONE = {
  processed: "success",
  received: "info",
  skipped: "attention",
  failed: "critical",
};

const roleLabel = (role) => {
  if (role === "trigger") return "Sends a message";
  if (role === "suppress") return "Cancels reminders";
  return "Logged only";
};

const formatTime = (value) => {
  if (!value) return "—";
  try {
    return new Date(value).toLocaleString();
  } catch (e) {
    return String(value);
  }
};

const WebhookEndpoints = () => {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [providers, setProviders] = useState([]);
  const [endpoints, setEndpoints] = useState([]);
  const [revealedSecrets, setRevealedSecrets] = useState({});
  const [deliveries, setDeliveries] = useState([]);
  const [expandedDelivery, setExpandedDelivery] = useState(null);
  const [newProvider, setNewProvider] = useState("shopflo");

  const load = useCallback(() => {
    setLoading(true);
    return Api.get("/api/webhooks/endpoints")
      .then((response) => {
        setProviders(response?.data?.providers || []);
        setEndpoints(response?.data?.endpoints || []);
        setError(null);
      })
      .catch((e) => setError(e?.response?.data?.error || "Could not load webhook endpoints."))
      .finally(() => setLoading(false));
  }, []);

  const loadDeliveries = useCallback(() => {
    Api.get("/api/webhooks/endpoints/deliveries")
      .then((response) => setDeliveries(response?.data?.deliveries || []))
      .catch(() => setDeliveries([]));
  }, []);

  useEffect(() => {
    load().then(loadDeliveries);
  }, [load, loadDeliveries]);

  const providerOptions = useMemo(
    () => providers.map((p) => ({ label: p.label, value: p.key })),
    [providers]
  );

  const takenProviders = useMemo(
    () => new Set(endpoints.map((e) => e.provider)),
    [endpoints]
  );

  const availableProviderOptions = useMemo(
    () => providerOptions.filter((o) => !takenProviders.has(o.value)),
    [providerOptions, takenProviders]
  );

  const applyEndpoint = (endpoint) => {
    setEndpoints((prev) => {
      const next = prev.filter((e) => e.id !== endpoint.id);
      next.push(endpoint);
      return next.sort((a, b) => a.provider.localeCompare(b.provider));
    });
    if (endpoint.secret) {
      setRevealedSecrets((prev) => ({ ...prev, [endpoint.id]: endpoint.secret }));
    }
  };

  const createEndpoint = () => {
    setSaving(true);
    Api.post("/api/webhooks/endpoints", { provider: newProvider })
      .then((response) => {
        applyEndpoint(response?.data?.endpoint);
        setNotice("Endpoint created. Copy the signing secret now. It is only shown once.");
      })
      .catch((e) => setError(e?.response?.data?.error || "Could not create the endpoint."))
      .finally(() => setSaving(false));
  };

  const updateEndpoint = (endpoint, attrs) => {
    setSaving(true);
    Api.patch(`/api/webhooks/endpoints/${endpoint.id}`, attrs)
      .then((response) => {
        applyEndpoint(response?.data?.endpoint);
        setError(null);
      })
      .catch((e) => setError(e?.response?.data?.error || "Could not save."))
      .finally(() => setSaving(false));
  };

  const rotateSecret = (endpoint) => {
    setSaving(true);
    Api.post(`/api/webhooks/endpoints/${endpoint.id}/rotate_secret`)
      .then((response) => {
        applyEndpoint(response?.data?.endpoint);
        setNotice("New secret generated. Update it in the provider's dashboard now.");
      })
      .catch((e) => setError(e?.response?.data?.error || "Could not rotate the secret."))
      .finally(() => setSaving(false));
  };

  const replayDelivery = (delivery) => {
    Api.post("/api/webhooks/endpoints/replay", { id: delivery.id })
      .then(() => {
        setNotice(`Delivery ${delivery.id} queued for reprocessing.`);
        setTimeout(loadDeliveries, 1500);
      })
      .catch((e) => setError(e?.response?.data?.error || "Could not replay."));
  };

  const setEventSetting = (endpoint, eventName, attrs) => {
    updateEndpoint(endpoint, { eventConfig: { [eventName]: attrs } });
  };

  const copy = (value) => {
    if (navigator?.clipboard) {
      navigator.clipboard.writeText(value);
      setNotice("Copied to clipboard.");
    }
  };

  if (loading) {
    return (
      <Box padding="600">
        <InlineStack align="center">
          <Spinner accessibilityLabel={I18n.t("webhook_endpoints.loading_webhook_endpoints")} size="large" />
        </InlineStack>
      </Box>
    );
  }

  return (
    <Page
      backAction={{
        content: I18n.t("integrations.title", { defaultValue: "Integrations" }),
        onAction: () => navigateTo("/integrations"),
      }}
      title={I18n.t("webhooks.page_title")}
      subtitle={I18n.t("webhooks.page_subtitle")}
      fullWidth={true}
    >
      <BlockStack gap="400">

      {error && (
        <Banner tone="critical" onDismiss={() => setError(null)}>
          {error}
        </Banner>
      )}
      {notice && (
        <Banner tone="info" onDismiss={() => setNotice(null)}>
          {notice}
        </Banner>
      )}

      {endpoints.length === 0 && (
        <Card>
          <EmptyState
            heading={I18n.t("webhook_endpoints.no_webhook_endpoints_yet")}
            action={{
              content: I18n.t("webhook_endpoints.create_endpoint"),
              onAction: createEndpoint,
              loading: saving,
            }}
            image=""
          >
            <p>
              {I18n.t("webhook_endpoints.create_an_endpoint_to_get_a")}
            </p>
          </EmptyState>
        </Card>
      )}

      {endpoints.map((endpoint) => (
        <BlockStack key={endpoint.id} gap="400">
          {/* Connection and delivery are two cards so neither runs past the
              five fields Built for Shopify allows in one. */}
          <Card padding="600">
            <BlockStack gap="400">
              <InlineStack align="space-between" blockAlign="center" wrap>
                <InlineStack gap="200" blockAlign="center">
                  <Text as="h3" variant="headingMd">
                    {providers.find((p) => p.key === endpoint.provider)?.label || endpoint.provider}
                  </Text>
                  <Badge tone={endpoint.enabled ? "success" : undefined}>
                    {endpoint.enabled ? "Live" : "Paused"}
                  </Badge>
                  {endpoint.lastReceivedAt ? (
                    <Badge tone="info">{`Last event ${formatTime(endpoint.lastReceivedAt)}`}</Badge>
                  ) : (
                    <Badge tone="attention">{I18n.t("webhook_endpoints.no_events_received_yet")}</Badge>
                  )}
                </InlineStack>
                <Button
                  variant="plain"
                  tone={endpoint.enabled ? "critical" : undefined}
                  onClick={() => updateEndpoint(endpoint, { enabled: !endpoint.enabled })}
                  loading={saving}
                >
                  {endpoint.enabled ? "Pause" : "Resume"}
                </Button>
              </InlineStack>

              <TextField
                label={I18n.t("webhook_endpoints.webhook_url")}
                value={endpoint.url}
                readOnly
                autoComplete="off"
                connectedRight={<Button onClick={() => copy(endpoint.url)}>{I18n.t("webhook_endpoints.copy")}</Button>}
                helpText={I18n.t("webhook_endpoints.this_url_identifies_your_store_treat")}
              />

              <InlineStack gap="300" wrap blockAlign="end">
                <Box minWidth="220px">
                  <Select
                    label={I18n.t("webhook_endpoints.verification")}
                    options={SIGNATURE_SCHEMES}
                    value={endpoint.signatureScheme}
                    onChange={(value) => updateEndpoint(endpoint, { signatureScheme: value })}
                  />
                </Box>
                <Box minWidth="220px">
                  <TextField
                    label={I18n.t("webhook_endpoints.signature_header")}
                    value={endpoint.signatureHeader}
                    disabled={endpoint.signatureScheme === "none"}
                    autoComplete="off"
                    onChange={(value) => updateEndpoint(endpoint, { signatureHeader: value })}
                  />
                </Box>
              </InlineStack>

              <TextField
                label={I18n.t("webhook_endpoints.signing_secret")}
                value={revealedSecrets[endpoint.id] || `••••••••••••${endpoint.secretHint || ""}`}
                readOnly
                autoComplete="off"
                connectedRight={
                  <InlineStack gap="100">
                    {revealedSecrets[endpoint.id] && (
                      <Button onClick={() => copy(revealedSecrets[endpoint.id])}>{I18n.t("webhook_endpoints.copy")}</Button>
                    )}
                    <Button onClick={() => rotateSecret(endpoint)} loading={saving}>
                      {I18n.t("webhook_endpoints.rotate")}
                    </Button>
                  </InlineStack>
                }
                helpText={I18n.t("webhook_endpoints.shown_in_full_only_when_created")}
              />

              <Checkbox
                label={I18n.t("webhook_endpoints.mirror_every_delivery_to_slack")}
                checked={endpoint.mirrorToSlack}
                onChange={(value) => updateEndpoint(endpoint, { mirrorToSlack: value })}
                helpText={I18n.t("webhook_endpoints.useful_while_you_are_validating_a")}
              />
            </BlockStack>
          </Card>

          <Card padding="600">
            <BlockStack gap="400">
              <BlockStack gap="200">
                <Text as="h4" variant="headingSm">
                  {I18n.t("webhook_endpoints.events")}
                </Text>
                {endpoint.events.map((event) => (
                  <Box
                    key={event.name}
                    padding="300"
                    borderColor="border"
                    borderWidth="025"
                    borderRadius="200"
                  >
                    <InlineStack align="space-between" blockAlign="start" wrap gap="300">
                      <BlockStack gap="100">
                        <InlineStack gap="200" blockAlign="center">
                          <Text as="span" variant="bodyMd" fontWeight="semibold">
                            {event.label || event.name}
                          </Text>
                          <Badge tone={event.role === "trigger" ? "info" : undefined}>
                            {roleLabel(event.role)}
                          </Badge>
                        </InlineStack>
                        {event.description && (
                          <Text as="p" tone="subdued" variant="bodySm">
                            {event.description}
                          </Text>
                        )}
                        {event.role === "trigger" && event.enabled && (
                          <Button
                            variant="plain"
                            onClick={() => navigateTo("/features/whatsapp")}
                          >
                            {I18n.t("webhook_endpoints.configure_the_message_for_this_event")}
                          </Button>
                        )}
                      </BlockStack>

                      <InlineStack gap="300" blockAlign="center">
                        {event.role === "trigger" && (
                          <Box minWidth="150px">
                            <TextField
                              label={I18n.t("webhook_endpoints.amount_multiplier")}
                              type="number"
                              step={0.01}
                              min={0}
                              value={String(event.amountScale)}
                              autoComplete="off"
                              onChange={(value) =>
                                setEventSetting(endpoint, event.name, { amountScale: value })
                              }
                              helpText={I18n.t("webhook_endpoints.0_01_if_the_provider_sends")}
                            />
                          </Box>
                        )}
                        <Checkbox
                          label={event.enabled ? "On" : "Off"}
                          checked={event.enabled}
                          disabled={event.role === "ignore"}
                          onChange={(value) =>
                            setEventSetting(endpoint, event.name, { enabled: value })
                          }
                        />
                      </InlineStack>
                    </InlineStack>
                  </Box>
                ))}
              </BlockStack>

              <InlineStack gap="400">
                <Text as="span" tone="subdued" variant="bodySm">
                  {`Received ${endpoint.counters.received} · Processed ${endpoint.counters.processed} · Skipped ${endpoint.counters.skipped} · Failed ${endpoint.counters.failed}`}
                </Text>
              </InlineStack>
            </BlockStack>
          </Card>
        </BlockStack>
      ))}

      {endpoints.length > 0 && availableProviderOptions.length > 0 && (
        <Card padding="600">
            <InlineStack gap="300" blockAlign="end">
              <Box minWidth="260px">
                <Select
                  label={I18n.t("webhook_endpoints.add_another_provider")}
                  options={availableProviderOptions}
                  value={newProvider}
                  onChange={setNewProvider}
                />
              </Box>
              <Button onClick={createEndpoint} loading={saving}>
                {I18n.t("webhook_endpoints.create_endpoint")}
              </Button>
            </InlineStack>
          
        </Card>
      )}

      <Card padding="600">
          <BlockStack gap="300">
            <InlineStack align="space-between" blockAlign="center">
              <Text as="h3" variant="headingMd">
                {I18n.t("webhook_endpoints.recent_deliveries")}
              </Text>
              <Button variant="plain" onClick={loadDeliveries}>
                {I18n.t("webhook_endpoints.refresh")}
              </Button>
            </InlineStack>

            {deliveries.length === 0 && (
              <Text as="p" tone="subdued">
                {I18n.t("webhook_endpoints.nothing_received_yet_once_your_provider")}
              </Text>
            )}

            {deliveries.map((delivery) => (
              <Box
                key={delivery.id}
                padding="300"
                borderColor="border"
                borderWidth="025"
                borderRadius="200"
              >
                <BlockStack gap="200">
                  <InlineStack align="space-between" blockAlign="center" wrap gap="200">
                    <InlineStack gap="200" blockAlign="center">
                      <Badge tone={STATUS_TONE[delivery.status]}>{delivery.status}</Badge>
                      <Text as="span" variant="bodyMd" fontWeight="semibold">
                        {delivery.eventName || "unknown event"}
                      </Text>
                      <Text as="span" tone="subdued" variant="bodySm">
                        {formatTime(delivery.receivedAt)}
                      </Text>
                    </InlineStack>
                    <InlineStack gap="200">
                      <Button
                        variant="plain"
                        onClick={() =>
                          setExpandedDelivery(
                            expandedDelivery === delivery.id ? null : delivery.id
                          )
                        }
                      >
                        {expandedDelivery === delivery.id ? "Hide payload" : "View payload"}
                      </Button>
                      {(delivery.status === "failed" || delivery.status === "skipped") && (
                        <Button variant="plain" onClick={() => replayDelivery(delivery)}>
                          {I18n.t("webhook_endpoints.replay")}
                        </Button>
                      )}
                    </InlineStack>
                  </InlineStack>

                  {(delivery.skipReason || delivery.error) && (
                    <Text as="p" tone={delivery.error ? "critical" : "subdued"} variant="bodySm">
                      {delivery.error || delivery.skipReason}
                    </Text>
                  )}

                  <Collapsible
                    open={expandedDelivery === delivery.id}
                    id={`delivery-${delivery.id}`}
                  >
                    <Box background="bg-surface-secondary" padding="300" borderRadius="200">
                      <pre style={{ whiteSpace: "pre-wrap", wordBreak: "break-word", margin: 0 }}>
                        {JSON.stringify(delivery.payload, null, 2)}
                      </pre>
                    </Box>
                  </Collapsible>
                </BlockStack>
              </Box>
            ))}
          </BlockStack>
        
      </Card>
      </BlockStack>
    </Page>
  );
};

export default WebhookEndpoints;

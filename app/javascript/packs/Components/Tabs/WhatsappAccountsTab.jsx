import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  Card,
  BlockStack,
  Box,
  Text,
  Button,
  Banner,
  InlineStack,
  Badge,
  Spinner,
  Divider,
  TextField,
  Select,
  Link,
} from "@shopify/polaris";
import useApi from "../../Hooks/useApi";
import WhatsappErrorBanner from "../WhatsappErrorBanner";
import { navigateTo } from "../../../utils/navigate";

import I18n from "../../i18n-lang";

// Meta serves the WhatsApp Embedded Signup dialog from several hosts
// (facebook.com, www., web., business., and localised variants), so match on the
// hostname rather than a fixed list. Checking the parsed hostname — not a string
// suffix — is what keeps a lookalike such as https://evilfacebook.com out: its
// hostname neither equals "facebook.com" nor ends with ".facebook.com".
const isFacebookOrigin = (origin) => {
  try {
    const url = new URL(origin);
    if (url.protocol !== "https:") return false;
    return url.hostname === "facebook.com" || url.hostname.endsWith(".facebook.com");
  } catch (_e) {
    return false;
  }
};
const META_APP_ID = process.env.META_APP_ID;
const META_CONFIG_ID = process.env.META_CONFIG_ID;
const META_GRAPH_API_VERSION = process.env.META_GRAPH_API_VERSION || "v22.0";

const SDK_SCRIPT_ID = "facebook-jssdk";

const loadFacebookSdk = () =>
  new Promise((resolve, reject) => {
    if (window.FB) return resolve(window.FB);
    if (document.getElementById(SDK_SCRIPT_ID)) {
      const wait = setInterval(() => {
        if (window.FB) {
          clearInterval(wait);
          resolve(window.FB);
        }
      }, 100);
      return;
    }
    const script = document.createElement("script");
    script.id = SDK_SCRIPT_ID;
    script.async = true;
    script.defer = true;
    script.crossOrigin = "anonymous";
    script.src = "https://connect.facebook.net/en_US/sdk.js";
    script.onload = () => {
      try {
        window.FB.init({
          appId: META_APP_ID,
          autoLogAppEvents: true,
          xfbml: true,
          version: META_GRAPH_API_VERSION,
        });
        resolve(window.FB);
      } catch (err) {
        reject(err);
      }
    };
    script.onerror = reject;
    document.body.appendChild(script);
  });

const statusBadge = (status) => {
  switch (status) {
    case "verified":
      return <Badge tone="success">{I18n.t("whatsapp_accounts_tab.verified")}</Badge>;
    case "pending_verification":
      return <Badge tone="attention">{I18n.t("whatsapp_accounts_tab.pending_verification")}</Badge>;
    case "disabled":
      return <Badge tone="critical">{I18n.t("whatsapp_accounts_tab.disabled")}</Badge>;
    default:
      return <Badge>{I18n.t("whatsapp_accounts_tab.not_connected")}</Badge>;
  }
};

const WhatsappAccountsTab = () => {
  const [signupData, setSignupData] = useState(null);
  const [signupError, setSignupError] = useState(null);
  const [submitting, setSubmitting] = useState(false);
  const messageListenerRef = useRef(null);
  // Persist which accounts we've already auto-synced templates for, so reloads
  // don't re-pull. Keyed per account id.
  const autoSyncedRef = useRef({});

  const [{ data: accountsData, loading: loadingAccounts, error: accountsError }, refetchAccounts] =
    useApi({ url: "/api/whatsapp/accounts", method: "GET" }, { manual: false });

  const [, postAccount] = useApi({ url: "/api/whatsapp/accounts", method: "POST" }, { manual: true });
  const [, patchAccount] = useApi({ url: "/api/whatsapp/accounts", method: "PATCH" }, { manual: true });
  const [, deleteAccount] = useApi({ url: "/api/whatsapp/accounts", method: "DELETE" }, { manual: true });
  const [, postTemplatesSync] = useApi(
    { url: "/api/whatsapp/templates/sync", method: "POST" },
    { manual: true }
  );

  const accounts = accountsData?.accounts || [];

  // First-connect template prefetch — once per newly connected account.
  useEffect(() => {
    accounts.forEach((acc) => {
      if (!acc?.id || autoSyncedRef.current[acc.id]) return;
      const storageKey = `whatsapp:auto-synced:${acc.id}`;
      try {
        if (window.localStorage.getItem(storageKey)) {
          autoSyncedRef.current[acc.id] = true;
          return;
        }
      } catch (_) {
        /* localStorage disabled */
      }
      autoSyncedRef.current[acc.id] = true;
      postTemplatesSync({ params: { account_id: acc.id } })
        .then(() => {
          try {
            window.localStorage.setItem(storageKey, "1");
          } catch (_) {
            /* ignore */
          }
        })
        .catch(() => {
          autoSyncedRef.current[acc.id] = false;
        });
    });
  }, [accounts, postTemplatesSync]);

  useEffect(() => {
    const onMessage = (event) => {
      // Embedded Signup is hosted by Meta; only accept the WABA / phone ids
      // from Facebook itself.
      if (!isFacebookOrigin(event.origin)) return;
      try {
        const data = typeof event.data === "string" ? JSON.parse(event.data) : event.data;
        if (data?.type === "WA_EMBEDDED_SIGNUP") {
          if (data.event === "FINISH") {
            setSignupData((prev) => ({
              ...(prev || {}),
              waba_id: data.data?.waba_id,
              phone_number_id: data.data?.phone_number_id,
            }));
          } else if (data.event === "CANCEL") {
            setSignupError("Signup was cancelled.");
          } else if (data.event === "ERROR") {
            setSignupError(data.data?.error_message || "Signup error");
          }
        }
      } catch (_) {}
    };
    window.addEventListener("message", onMessage);
    messageListenerRef.current = onMessage;
    return () => window.removeEventListener("message", onMessage);
  }, []);

  const submitToBackend = useCallback(
    async ({ code, waba_id, phone_number_id }) => {
      setSubmitting(true);
      setSignupError(null);
      try {
        await postAccount({ data: { code, waba_id, phone_number_id } });
        await refetchAccounts();
        setSignupData(null);
      } catch (err) {
        const msg = err?.response?.data?.error || err?.message || "Failed to connect WhatsApp account";
        setSignupError(msg);
      } finally {
        setSubmitting(false);
      }
    },
    [postAccount, refetchAccounts]
  );

  const handleConnect = useCallback(async () => {
    setSignupError(null);
    if (!META_APP_ID || !META_CONFIG_ID) {
      setSignupError("Meta App ID or Config ID not configured.");
      return;
    }
    try {
      const FB = await loadFacebookSdk();
      FB.login(
        (response) => {
          if (response.authResponse?.code) {
            const code = response.authResponse.code;
            setSignupData((prev) => {
              const merged = { ...(prev || {}), code };
              if (merged.code) submitToBackend(merged);
              return merged;
            });
          } else {
            setSignupError("Login was cancelled or did not return a code.");
          }
        },
        {
          config_id: META_CONFIG_ID,
          response_type: "code",
          override_default_response_type: true,
          extras: { setup: {}, featureType: "whatsapp_business_app_onboarding" },
        }
      );
    } catch (err) {
      setSignupError(err?.message || "Failed to load Meta SDK");
    }
  }, [submitToBackend]);

  const handleDisconnect = useCallback(
    async (acc) => {
      const many = accounts.length > 1;
      const msg = many
        ? `Disconnect ${acc.displayLabel || acc.displayPhoneNumber || "this number"}? Events routed to it will fall back to your default number.`
        : "Disconnect this WhatsApp account? You'll need to re-authorize to send messages.";
      if (!window.confirm(msg)) return;
      try {
        await deleteAccount({ url: `/api/whatsapp/accounts/${acc.id}` });
        await refetchAccounts();
      } catch (err) {
        setSignupError(err?.response?.data?.error || err?.message || "Failed to disconnect");
      }
    },
    [accounts.length, deleteAccount, refetchAccounts]
  );

  const handleMakeDefault = useCallback(
    async (acc) => {
      try {
        await patchAccount({ url: `/api/whatsapp/accounts/${acc.id}`, data: { is_default: true } });
        await refetchAccounts();
      } catch (err) {
        setSignupError(err?.response?.data?.error || err?.message || "Failed to set default");
      }
    },
    [patchAccount, refetchAccounts]
  );

  const handleRename = useCallback(
    async (acc, label) => {
      try {
        await patchAccount({ url: `/api/whatsapp/accounts/${acc.id}`, data: { label } });
        await refetchAccounts();
      } catch (err) {
        setSignupError(err?.response?.data?.error || err?.message || "Failed to rename");
      }
    },
    [patchAccount, refetchAccounts]
  );

  if (loadingAccounts && accounts.length === 0) {
    return (
      <Card>
        <Box padding="400">
          <InlineStack gap="200" align="center">
            <Spinner size="small" />
            <Text as="span">{I18n.t("whatsapp_accounts_tab.loading_whatsapp_numbers")}</Text>
          </InlineStack>
        </Box>
      </Card>
    );
  }

  return (
    <BlockStack gap="400">
      {signupError && (
        <Banner tone="critical" onDismiss={() => setSignupError(null)}>
          {signupError}
        </Banner>
      )}

      {accountsError && !signupError && (
        <Banner tone="critical">
                  {I18n.t("whatsapp_accounts_tab.failed_to_load_numbers", {
                    error: accountsError.message,
                  })}
                </Banner>
      )}

      {accounts.length === 0 ? (
        <>
          <Card>
            <Box padding="400">
              <BlockStack gap="300">
                <Text variant="headingMd" as="h2">
                  {I18n.t("whatsapp_accounts_tab.connect_your_whatsapp_business_account")}
                </Text>
                <Text as="p" tone="subdued">
                  {I18n.t("whatsapp_accounts_tab.connect_via_meta_s_embedded_signup")}
                </Text>
                <Banner tone="info">
                  <Text as="p" variant="bodySm">
                    {I18n.t("whatsapp_accounts_tab.need_meta_approved_account", {
                      account: I18n.t(
                        "whatsapp_accounts_tab.meta_approved_whatsapp_business_account"
                      ),
                    })}{" "}
                    <Link url="https://business.facebook.com/wa/manage/home/" external>
                      {I18n.t("whatsapp_accounts_tab.check_if_you_already_have_one")}
                    </Link>
                    .
                  </Text>
                </Banner>
                <InlineStack gap="200">
                  <Button variant="primary" onClick={handleConnect} loading={submitting}>
                    {I18n.t("whatsapp_accounts_tab.connect_whatsapp_account")}
                  </Button>
                </InlineStack>
              </BlockStack>
            </Box>
          </Card>
          <ConnectHowItWorks />
        </>
      ) : (
        <>
          <InlineStack align="space-between" blockAlign="center">
            <Text variant="headingMd" as="h2">
              {I18n.t("whatsapp_accounts_tab.whatsapp_numbers")}
            </Text>
            <InlineStack gap="200">
              <Button variant="plain" onClick={refetchAccounts} loading={loadingAccounts}>
                {I18n.t("whatsapp_accounts_tab.refresh")}
              </Button>
              <Button variant="primary" onClick={handleConnect} loading={submitting}>
                {I18n.t("whatsapp_accounts_tab.add_number")}
              </Button>
            </InlineStack>
          </InlineStack>

          <Text as="p" tone="subdued" variant="bodySm">
            {I18n.t("whatsapp_accounts_tab.the")} <strong>{I18n.t("whatsapp_accounts_tab.default")}</strong> {I18n.t("whatsapp_accounts_tab.number_is_used_for_any_notification")}
          </Text>

          {accounts.map((account) => (
            <AccountCard
              key={account.id}
              account={account}
              isOnly={accounts.length === 1}
              onChange={refetchAccounts}
              onDisconnect={() => handleDisconnect(account)}
              onMakeDefault={() => handleMakeDefault(account)}
              onRename={(label) => handleRename(account, label)}
            />
          ))}
        </>
      )}
    </BlockStack>
  );
};

const AccountCard = ({ account, isOnly, onChange, onDisconnect, onMakeDefault, onRename }) => {
  const [labelDraft, setLabelDraft] = useState(account.label || "");
  const [editingLabel, setEditingLabel] = useState(false);

  return (
    <Card>
      <Box padding="400">
        <BlockStack gap="400">
          <InlineStack align="space-between" blockAlign="center">
            <InlineStack gap="200" blockAlign="center">
              <Text variant="headingMd" as="h3">
                {account.displayLabel || account.displayPhoneNumber || "WhatsApp number"}
              </Text>
              {account.isDefault && <Badge tone="info">{I18n.t("whatsapp_accounts_tab.default_2")}</Badge>}
              {statusBadge(account.status)}
            </InlineStack>
            {!account.isDefault && (
              <Button variant="plain" onClick={onMakeDefault}>
                {I18n.t("whatsapp_accounts_tab.make_default")}
              </Button>
            )}
          </InlineStack>

          <Divider />

          <BlockStack gap="200">
            <DetailRow label={I18n.t("whatsapp_accounts_tab.sending_from")} value={account.displayPhoneNumber || "—"} />
            <DetailRow label={I18n.t("whatsapp_accounts_tab.verified_name")} value={account.verifiedName || "—"} />
            {editingLabel ? (
              <InlineStack gap="200" blockAlign="end">
                <Box minWidth="240px">
                  <TextField
                    label={I18n.t("whatsapp_accounts_tab.label")}
                    value={labelDraft}
                    onChange={setLabelDraft}
                    autoComplete="off"
                    placeholder={I18n.t("whatsapp_accounts_tab.e_g_support_marketing")}
                  />
                </Box>
                <Button
                  onClick={async () => {
                    await onRename(labelDraft);
                    setEditingLabel(false);
                  }}
                >
                  {I18n.t("whatsapp_accounts_tab.save")}
                </Button>
                <Button variant="plain" onClick={() => setEditingLabel(false)}>
                  {I18n.t("whatsapp_accounts_tab.cancel")}
                </Button>
              </InlineStack>
            ) : (
              <InlineStack align="space-between" blockAlign="center">
                <Text as="span" tone="subdued">
                  {I18n.t("whatsapp_accounts_tab.label")}
                </Text>
                <InlineStack gap="200" blockAlign="center">
                  <Text as="span" fontWeight="medium">
                    {account.label || "—"}
                  </Text>
                  <Button variant="plain" onClick={() => setEditingLabel(true)}>
                    {I18n.t("whatsapp_accounts_tab.edit")}
                  </Button>
                </InlineStack>
              </InlineStack>
            )}
            {account.qualityRating &&
              account.qualityRating !== "GREEN" &&
              account.qualityRating !== "UNKNOWN" && (
                <Banner tone={account.qualityRating === "YELLOW" ? "warning" : "critical"}>
                  {I18n.t("whatsapp_accounts_tab.message_quality_is")} <strong>{account.qualityRating}</strong> {I18n.t("whatsapp_accounts_tab.for_this_number")}
                </Banner>
              )}
          </BlockStack>

          <TechnicalDetails account={account} />

          {!account.registeredAt && (
            <>
              <Banner tone="critical">
                <Text as="p" variant="bodySm">
                  {I18n.t("whatsapp_accounts_tab.number_not_registered_body", {
                    error: I18n.t(
                      "whatsapp_accounts_tab.133010_account_not_registered"
                    ),
                  })}
                  {account.registrationError
                    ? I18n.t("whatsapp_accounts_tab.meta_said", {
                        message: account.registrationError,
                      })
                    : ""}
                </Text>
              </Banner>
              <PhoneVerificationPanel accountId={account.id} onChange={onChange} />
            </>
          )}

          {account.status === "verified" && account.registeredAt && (
            <TestMessagePanel accountId={account.id} />
          )}

          <InlineStack gap="200" align="space-between" wrap>
            <Button variant="primary" onClick={() => navigateTo("/features/whatsapp/templates")}>
              {I18n.t("whatsapp_accounts_tab.manage_templates_automations")}
            </Button>
            <Button tone="critical" variant="plain" onClick={onDisconnect}>
              {isOnly ? "Disconnect" : "Disconnect this number"}
            </Button>
          </InlineStack>
        </BlockStack>
      </Box>
    </Card>
  );
};

const ConnectHowItWorks = () => {
  const steps = [
    {
      n: 1,
      title: I18n.t("whatsapp_accounts_tab.connect_your_number"),
      desc: "Authorize through Meta's Embedded Signup. We register your WABA and phone number.",
    },
    {
      n: 2,
      title: I18n.t("whatsapp_accounts_tab.templates_sync_automatically"),
      desc: "Once connected, your approved WhatsApp templates are pulled in for you — no manual step.",
    },
    {
      n: 3,
      title: I18n.t("whatsapp_accounts_tab.configure_notifications"),
      desc: "Bind a template to each event and choose which number it sends from — order placed, shipped, abandoned cart.",
    },
  ];

  return (
    <Card>
      <Box padding="500">
        <BlockStack gap="400">
          <Text as="h3" variant="headingMd">
            {I18n.t("whatsapp_accounts_tab.how_it_works")}
          </Text>
          <BlockStack gap="300">
            {steps.map((s) => (
              <InlineStack key={s.n} gap="300" blockAlign="start" wrap={false}>
                <Box
                  as="span"
                  background="bg-fill-brand"
                  padding="100"
                  borderRadius="full"
                  minWidth="32px"
                >
                  <Text
                    as="span"
                    variant="bodyMd"
                    fontWeight="bold"
                    alignment="center"
                    tone="text-inverse"
                  >
                    {s.n}
                  </Text>
                </Box>
                <BlockStack gap="050">
                  <Text as="h4" variant="headingSm">
                    {s.title}
                  </Text>
                  <Text as="p" tone="subdued" variant="bodySm">
                    {s.desc}
                  </Text>
                </BlockStack>
              </InlineStack>
            ))}
          </BlockStack>
        </BlockStack>
      </Box>
    </Card>
  );
};

const TestMessagePanel = ({ accountId }) => {
  const [to, setTo] = useState("");
  const [selectedTemplate, setSelectedTemplate] = useState("");
  const [sending, setSending] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [success, setSuccess] = useState(null);
  const [error, setError] = useState(null);

  const [{ data: templatesData, loading: loadingTemplates }, refetchTemplates] = useApi(
    { url: "/api/whatsapp/templates", method: "GET", params: { account_id: accountId } },
    { manual: false }
  );
  const [, syncTemplatesApi] = useApi(
    { url: "/api/whatsapp/templates/sync", method: "POST" },
    { manual: true }
  );
  const [, postSend] = useApi(
    { url: "/api/whatsapp/test_messages", method: "POST" },
    { manual: true }
  );

  const handleSync = async () => {
    setError(null);
    setSyncing(true);
    try {
      await syncTemplatesApi({ params: { account_id: accountId } });
      await refetchTemplates();
    } catch (err) {
      setError(err?.response?.data?.error || err?.message || "Couldn't refresh from WhatsApp");
    } finally {
      setSyncing(false);
    }
  };

  const approved = (templatesData?.templates || []).filter((t) => t.status === "approved");
  const options = [
    { label: approved.length ? "Choose a template…" : "No approved templates yet", value: "" },
    ...approved.map((t) => ({ label: `${t.name} (${t.language})`, value: `${t.name}::${t.language}` })),
  ];

  const handleSend = async () => {
    setError(null);
    setSuccess(null);
    if (!to || !selectedTemplate) return;
    const [template_name, language] = selectedTemplate.split("::");

    setSending(true);
    try {
      const { data } = await postSend({
        data: { to, template_name, language, account_id: accountId },
      });
      setSuccess(`Sent. Message id: ${data?.messageId || "ok"}`);
    } catch (err) {
      setError(err?.response?.data?.error || err?.message || "Send failed");
    } finally {
      setSending(false);
    }
  };

  return (
    <Card background="bg-surface-secondary">
      <Box padding="400">
        <BlockStack gap="300">
          <InlineStack align="space-between" blockAlign="center">
            <Text variant="headingSm" as="h3">
              {I18n.t("whatsapp_accounts_tab.send_a_test_message")}
            </Text>
            <Button variant="plain" onClick={handleSync} loading={syncing || loadingTemplates}>
              {I18n.t("whatsapp_accounts_tab.refresh_from_whatsapp")}
            </Button>
          </InlineStack>
          <Text as="p" tone="subdued" variant="bodySm">
            {I18n.t("whatsapp_accounts_tab.sends_one_template_message_from_this")}
          </Text>

          {error && <WhatsappErrorBanner rawMessage={error} onDismiss={() => setError(null)} />}
          {success && (
            <Banner tone="success" onDismiss={() => setSuccess(null)}>
              {success}
            </Banner>
          )}

          <InlineStack gap="200" blockAlign="end">
            <Box minWidth="220px">
              <TextField
                label={I18n.t("whatsapp_accounts_tab.recipient_with_country_code")}
                placeholder="e.g. 919999988888"
                value={to}
                onChange={setTo}
                autoComplete="off"
              />
            </Box>
            <Box minWidth="240px">
              <Select
                label={I18n.t("whatsapp_accounts_tab.template")}
                options={options}
                value={selectedTemplate}
                onChange={setSelectedTemplate}
                disabled={!approved.length}
              />
            </Box>
            <Button
              variant="primary"
              loading={sending}
              disabled={!to || !selectedTemplate}
              onClick={handleSend}
            >
              {I18n.t("whatsapp_accounts_tab.send_test")}
            </Button>
          </InlineStack>
        </BlockStack>
      </Box>
    </Card>
  );
};

const PhoneVerificationPanel = ({ accountId, onChange }) => {
  const [pin, setPin] = useState("");
  const [code, setCode] = useState("");
  const [codeMethod, setCodeMethod] = useState("SMS");
  const [busy, setBusy] = useState(false);
  const [info, setInfo] = useState(null);
  const [error, setError] = useState(null);

  const [, postRegister] = useApi(
    { url: "/api/whatsapp/phone_number/register", method: "POST" },
    { manual: true }
  );
  const [, postRequestCode] = useApi(
    { url: "/api/whatsapp/phone_number/request_code", method: "POST" },
    { manual: true }
  );
  const [, postVerifyCode] = useApi(
    { url: "/api/whatsapp/phone_number/verify_code", method: "POST" },
    { manual: true }
  );

  const run = useCallback(
    async (fn, onSuccess) => {
      setBusy(true);
      setError(null);
      setInfo(null);
      try {
        await fn();
        if (onSuccess) onSuccess();
        if (onChange) await onChange();
      } catch (err) {
        setError(err?.response?.data?.error || err?.message || "Request failed");
      } finally {
        setBusy(false);
      }
    },
    [onChange]
  );

  return (
    <Card background="bg-surface-secondary">
      <Box padding="400">
        <BlockStack gap="400">
          <Text variant="headingSm" as="h3">
            {I18n.t("whatsapp_accounts_tab.verify_your_number")}
          </Text>
          <Text as="p" tone="subdued" variant="bodySm">
            {I18n.t("whatsapp_accounts_tab.set_a_6_digit_pin_to")}
          </Text>

          {error && (
            <Banner tone="critical" onDismiss={() => setError(null)}>
              {error}
            </Banner>
          )}
          {info && (
            <Banner tone="success" onDismiss={() => setInfo(null)}>
              {info}
            </Banner>
          )}

          <BlockStack gap="200">
            <Text variant="headingXs" as="h4">
              {I18n.t("whatsapp_accounts_tab.step_1_register_with_6_digit")}
            </Text>
            <InlineStack gap="200" blockAlign="end">
              <Box minWidth="200px">
                <TextField
                  label={I18n.t("whatsapp_accounts_tab.6_digit_pin")}
                  type="text"
                  value={pin}
                  onChange={setPin}
                  maxLength={6}
                  autoComplete="off"
                />
              </Box>
              <Button
                variant="primary"
                loading={busy}
                disabled={pin.length !== 6}
                onClick={() =>
                  run(
                    () => postRegister({ data: { pin, account_id: accountId } }),
                    () => setInfo("Number registered. WhatsApp Cloud is now ready.")
                  )
                }
              >
                {I18n.t("whatsapp_accounts_tab.register_number")}
              </Button>
            </InlineStack>
          </BlockStack>

          <Divider />

          <BlockStack gap="200">
            <Text variant="headingXs" as="h4">
              {I18n.t("whatsapp_accounts_tab.step_2_only_if_needed_verify")}
            </Text>
            <Text as="p" tone="subdued" variant="bodySm">
              {I18n.t("whatsapp_accounts_tab.use_this_if_meta_is_asking")}
            </Text>
            <InlineStack gap="200" blockAlign="end">
              <Box minWidth="160px">
                <Select
                  label={I18n.t("whatsapp_accounts_tab.method")}
                  options={[
                    { label: I18n.t("whatsapp_accounts_tab.sms"), value: "SMS" },
                    { label: I18n.t("whatsapp_accounts_tab.voice_call"), value: "VOICE" },
                  ]}
                  value={codeMethod}
                  onChange={setCodeMethod}
                />
              </Box>
              <Button
                loading={busy}
                onClick={() =>
                  run(
                    () => postRequestCode({ data: { code_method: codeMethod, account_id: accountId } }),
                    () => setInfo(`Code requested via ${codeMethod}.`)
                  )
                }
              >
                {I18n.t("whatsapp_accounts_tab.request_code")}
              </Button>
            </InlineStack>
            <InlineStack gap="200" blockAlign="end">
              <Box minWidth="200px">
                <TextField
                  label={I18n.t("whatsapp_accounts_tab.verification_code")}
                  type="text"
                  value={code}
                  onChange={setCode}
                  maxLength={10}
                  autoComplete="off"
                />
              </Box>
              <Button
                variant="primary"
                loading={busy}
                disabled={code.length < 4}
                onClick={() =>
                  run(
                    () => postVerifyCode({ data: { code, account_id: accountId } }),
                    () => setInfo("Code accepted.")
                  )
                }
              >
                {I18n.t("whatsapp_accounts_tab.verify_code")}
              </Button>
            </InlineStack>
          </BlockStack>
        </BlockStack>
      </Box>
    </Card>
  );
};

const DetailRow = ({ label, value, mono }) => (
  <InlineStack align="space-between" blockAlign="center">
    <Text as="span" tone="subdued">
      {label}
    </Text>
    <Text as="span" fontWeight="medium" {...(mono ? { fontFamily: "mono" } : {})}>
      {value}
    </Text>
  </InlineStack>
);

const TechnicalDetails = ({ account }) => {
  const [open, setOpen] = useState(false);
  return (
    <BlockStack gap="200">
      <Button variant="plain" disclosure={open ? "up" : "down"} onClick={() => setOpen((v) => !v)}>
        {open ? "Hide technical details" : "Show technical details"}
      </Button>
      {open && (
        <Box padding="300" borderColor="border" borderWidth="025" borderRadius="200">
          <BlockStack gap="200">
            <DetailRow label={I18n.t("whatsapp_accounts_tab.waba_id")} value={account.wabaId || "—"} mono />
            <DetailRow label={I18n.t("whatsapp_accounts_tab.phone_number_id")} value={account.phoneNumberId || "—"} mono />
            <DetailRow label={I18n.t("whatsapp_accounts_tab.quality_rating")} value={account.qualityRating || "—"} />
            <DetailRow
              label={I18n.t("whatsapp_accounts_tab.webhook")}
              value={account.webhookSubscribedAt ? "Subscribed" : "Not subscribed"}
            />
            <DetailRow
              label={I18n.t("whatsapp_accounts_tab.last_synced")}
              value={account.lastSyncedAt ? new Date(account.lastSyncedAt).toLocaleString() : "—"}
            />
          </BlockStack>
        </Box>
      )}
    </BlockStack>
  );
};

export default WhatsappAccountsTab;

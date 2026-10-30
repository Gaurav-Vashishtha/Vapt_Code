import React from "react";
import {
  Card, BlockStack, InlineStack, Box, Text, Button, Icon, ProgressBar, Badge, Divider,
} from "@shopify/polaris";
import { CircleTickMajor } from "@shopify/polaris-icons";
import { navigateTo } from "../../../../utils/navigate";
import { t, formatNumber } from "./copy";

// The three things a first campaign needs, in the order they have to happen.
// Each row says what is missing and has the one button that fixes it, so the
// merchant never has to work out which other page to visit.
export const setupSteps = (overview, { onSync, syncing, onUpload } = {}) => {
  const account = overview?.account || {};
  const templates = overview?.templates || {};
  const contacts = overview?.contacts || {};
  const syncStatus = contacts.sync?.status;
  const syncRunning = ["queued", "running"].includes(syncStatus);

  const numberStep = account.ready_to_send
    ? {
        done: true,
        title: t("setup_step_number_done", "WhatsApp number connected"),
        detail: [account.verified_name, account.display_phone_number].filter(Boolean).join(" · "),
      }
    : account.connected
      ? {
          title: t("setup_step_number_verify", "Finish verifying your WhatsApp number"),
          detail: t(
            "setup_step_number_verify_detail",
            "Your number is connected but WhatsApp hasn't cleared it to send yet. Finish the last step to start sending."
          ),
          action: { content: t("setup_step_number_verify_action", "Finish verification"), url: "/features/whatsapp/account" },
        }
      : {
          title: t("setup_step_number", "Connect your WhatsApp Business number"),
          detail: t(
            "setup_step_number_detail",
            "Messages are sent from your own number, with your brand name. Takes about 5 minutes through Meta."
          ),
          action: { content: t("setup_step_number_action", "Connect number"), url: "/features/whatsapp/account" },
        };

  const messageStep =
    templates.approved > 0
      ? {
          done: true,
          title: t("setup_step_message_done", "Message approved by WhatsApp"),
          detail: t("setup_step_message_done_detail", "%{count} approved message(s) ready to send", {
            count: templates.approved,
          }),
        }
      : templates.pending > 0
        ? {
            waiting: true,
            title: t("setup_step_message_waiting", "Waiting for WhatsApp to approve your message"),
            detail: t(
              "setup_step_message_waiting_detail",
              "WhatsApp checks every campaign message first. This usually takes a few minutes to a few hours."
            ),
            action: { content: t("setup_step_message_view", "View messages"), url: "/features/whatsapp/templates" },
          }
        : {
            title: t("setup_step_message", "Get a message approved"),
            detail: t(
              "setup_step_message_detail",
              "WhatsApp only allows pre-approved messages for campaigns. Start from a ready-made one and send it for approval."
            ),
            action: { content: t("setup_step_message_action", "Choose a message"), url: "/features/whatsapp/templates" },
          };

  const contactsStep =
    contacts.total > 0
      ? {
          done: true,
          title: t("setup_step_contacts_done", "Contacts ready"),
          detail: t("setup_step_contacts_done_detail", "%{subscribed} of %{total} contacts can receive campaigns", {
            subscribed: formatNumber(contacts.subscribed),
            total: formatNumber(contacts.total),
          }),
        }
      : syncRunning
        ? {
            waiting: true,
            title: t("setup_step_contacts_syncing", "Bringing in your customers…"),
            detail: t(
              "setup_step_contacts_syncing_detail",
              "Customers and abandoned checkouts are being copied from your store. You can keep working."
            ),
          }
        : {
            title: t("setup_step_contacts", "Bring in your customers"),
            detail: t(
              "setup_step_contacts_detail",
              "Copy your Shopify customers and abandoned checkouts in, or upload a list."
            ),
            action: onSync && { content: t("setup_step_contacts_action", "Import from store"), onAction: onSync, loading: syncing },
            secondary: onUpload && { content: t("setup_step_contacts_upload", "Upload a list"), onAction: onUpload },
          };

  return [numberStep, messageStep, contactsStep];
};

export const isReadyToSend = (overview) =>
  !!overview?.account?.ready_to_send && (overview?.templates?.approved || 0) > 0;

const StepMarker = ({ index, done }) =>
  done ? (
    <Box minWidth="24px">
      <Icon source={CircleTickMajor} tone="success" />
    </Box>
  ) : (
    <div style={markerStyle}>
      <Text as="span" variant="bodySm" fontWeight="semibold">
        {index + 1}
      </Text>
    </div>
  );

const markerStyle = {
  width: 24,
  height: 24,
  minWidth: 24,
  borderRadius: "50%",
  border: "1.5px solid var(--p-color-border)",
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
};

const SetupChecklist = ({ steps }) => {
  const doneCount = steps.filter((s) => s.done).length;
  // Only the first unfinished step gets a primary button: that is the next thing to do.
  const nextIndex = steps.findIndex((s) => !s.done && !s.waiting);

  return (
    <Card>
      <BlockStack gap="400">
        <BlockStack gap="200">
          <InlineStack align="space-between" blockAlign="center" gap="200">
            <Text as="h2" variant="headingMd">
              {t("setup_title", "Set up WhatsApp campaigns")}
            </Text>
            <Text as="span" variant="bodySm" tone="subdued">
              {t("setup_progress", "%{done} of %{total} done", { done: doneCount, total: steps.length })}
            </Text>
          </InlineStack>
          <ProgressBar progress={(doneCount * 100) / steps.length} size="small" tone="primary" />
        </BlockStack>
        {steps.map((step, i) => (
          <React.Fragment key={i}>
            {i > 0 && <Divider />}
            <InlineStack gap="300" wrap={false} blockAlign="start">
              <StepMarker index={i} done={step.done} />
              <Box width="100%">
                <BlockStack gap="200">
                  <BlockStack gap="050">
                    <InlineStack gap="200" blockAlign="center">
                      <Text as="h3" variant="headingSm" tone={step.done ? "subdued" : undefined}>
                        {step.title}
                      </Text>
                      {step.waiting && <Badge tone="info">{t("setup_in_progress", "In progress")}</Badge>}
                    </InlineStack>
                    {step.detail && (
                      <Text as="p" variant="bodySm" tone="subdued">
                        {step.detail}
                      </Text>
                    )}
                  </BlockStack>
                  {!step.done && (step.action || step.secondary) && (
                    <InlineStack gap="200">
                      {step.action && (
                        <Button
                          variant={i === nextIndex ? "primary" : undefined}
                          loading={step.action.loading}
                          onClick={step.action.onAction || (() => navigateTo(step.action.url))}
                        >
                          {step.action.content}
                        </Button>
                      )}
                      {step.secondary && <Button onClick={step.secondary.onAction}>{step.secondary.content}</Button>}
                    </InlineStack>
                  )}
                </BlockStack>
              </Box>
            </InlineStack>
          </React.Fragment>
        ))}
      </BlockStack>
    </Card>
  );
};

export default SetupChecklist;

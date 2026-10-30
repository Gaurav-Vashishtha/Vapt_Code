
import I18n from "../i18n-lang";// Translate Meta WhatsApp Cloud API error codes to human-readable copy.
// Returns { title, body, actionLabel?, actionHref? } so we can render a
// Banner + CTA at the points the error surfaces (Logs, Test send, Submit, …).
//
// The map covers the codes merchants will actually see day to day. Anything
// uncovered falls back to the raw Meta message so we don't hide useful info.

const TRANSLATIONS = {
  131000: {
    get title() {
      return I18n.t("whatsapp_error_messages.whatsapp_couldn_t_process_the_message");
    },
    body: "Something went wrong on WhatsApp's side. Try again in a minute — if it keeps happening, contact support.",
  },
  131008: {
    get title() {
      return I18n.t("whatsapp_error_messages.some_personalization_values_are_missing");
    },
    body: "One of the variables in your message wasn't filled in. Open the message and make sure every {{1}}, {{2}}, … is mapped to a customer/order field.",
    actionLabel: "Fix in Messages",
    actionHref: "/features/whatsapp/templates",
  },
  131009: {
    get title() {
      return I18n.t("whatsapp_error_messages.recipient_s_phone_number_is_invalid");
    },
    body: "The number on this order isn't a valid WhatsApp number. Check the customer's phone on the order.",
  },
  131016: {
    get title() {
      return I18n.t("whatsapp_error_messages.recipient_hasn_t_agreed_to_receive");
    },
    body: "WhatsApp requires customers to opt in before you can send them marketing messages. Switch this template to UTILITY or get explicit opt-in.",
  },
  131021: {
    get title() {
      return I18n.t("whatsapp_error_messages.recipient_can_t_be_reached_on");
    },
    body: "Either they don't have WhatsApp, or they've blocked your number.",
  },
  131026: {
    get title() {
      return I18n.t("whatsapp_error_messages.couldn_t_deliver_try_again");
    },
    body: "WhatsApp had trouble delivering this one. We'll retry automatically on the next send.",
  },
  131030: {
    get title() {
      return I18n.t("whatsapp_error_messages.recipient_isn_t_in_your_test");
    },
    body: "Your WhatsApp number is still in test mode. Add this customer's phone number to your allowed test recipients in Meta WhatsApp Manager, then resend.",
    actionLabel: "Open WhatsApp Manager",
    actionHref: "https://business.facebook.com/wa/manage/phone-numbers/",
  },
  131047: {
    get title() {
      return I18n.t("whatsapp_error_messages.conversation_window_has_expired");
    },
    body: "You can only send free-form replies within 24 hours of the customer's last message. Send a template message instead.",
  },
  131051: {
    get title() {
      return I18n.t("whatsapp_error_messages.message_type_not_supported");
    },
    body: "WhatsApp doesn't support this content type. Try a text or template message instead.",
  },
  132000: {
    get title() {
      return I18n.t("whatsapp_error_messages.wrong_number_of_personalization_values");
    },
    body: "The message has more {{1}}, {{2}}, … placeholders than your mapping covers (or vice versa). Open the message and add a value for every placeholder.",
    actionLabel: "Fix in Messages",
    actionHref: "/features/whatsapp/templates",
  },
  132001: {
    get title() {
      return I18n.t("whatsapp_error_messages.message_template_doesn_t_exist");
    },
    body: "This template was deleted or renamed on WhatsApp's side. Refresh your message list to pick a different one.",
    actionLabel: "Refresh messages",
    actionHref: "/features/whatsapp/templates",
  },
  132005: {
    get title() {
      return I18n.t("whatsapp_error_messages.message_text_is_too_long");
    },
    body: "Your message body exceeds WhatsApp's character limit (1024 chars). Shorten and resubmit for approval.",
  },
  132007: {
    get title() {
      return I18n.t("whatsapp_error_messages.template_is_paused");
    },
    body: "WhatsApp temporarily paused this template (usually for low quality). It will resume automatically — or you can submit a new variant.",
  },
  131053: {
    get title() {
      return I18n.t("whatsapp_error_messages.couldn_t_load_the_header_image");
    },
    body: "WhatsApp couldn't fetch this message's header image. Open the notification and set its header image — a fixed public JPG/PNG, or the product image — then turn it on again.",
    actionLabel: "Fix in Notifications",
    actionHref: "/features/whatsapp/templates",
  },
  132012: {
    get title() {
      return I18n.t("whatsapp_error_messages.image_video_document_not_available");
    },
    body: "We couldn't load the media for this message. Re-upload the file when editing the message.",
    actionLabel: "Fix in Messages",
    actionHref: "/features/whatsapp/templates",
  },
  132015: {
    get title() {
      return I18n.t("whatsapp_error_messages.template_is_disabled");
    },
    body: "WhatsApp disabled this template. Pick a different message or submit a new variant.",
  },
  132016: {
    get title() {
      return I18n.t("whatsapp_error_messages.template_was_rejected");
    },
    body: "WhatsApp rejected this template after review. Open the message to see WhatsApp's reason and edit accordingly.",
  },
  133000: {
    get title() {
      return I18n.t("whatsapp_error_messages.your_number_needs_to_be_re");
    },
    body: "Re-run the 6-digit PIN registration from your Account page.",
    actionLabel: "Go to Account",
    actionHref: "/features/whatsapp/account",
  },
  133010: {
    get title() {
      return I18n.t("whatsapp_error_messages.your_number_isn_t_fully_registered");
    },
    body: "Finish the 6-digit PIN registration on your Account page to start sending messages.",
    actionLabel: "Finish verification",
    actionHref: "/features/whatsapp/account",
  },
  133006: {
    get title() {
      return I18n.t("whatsapp_error_messages.your_business_verification_is_pending");
    },
    body: "Your number can send to a limited list of recipients until Meta verifies your business. Submit business verification in Meta Business Manager.",
    actionLabel: "Open Business Manager",
    actionHref: "https://business.facebook.com/settings/security",
  },
};

// Parse "(#131008) Required parameter is missing" → code + raw message.
const extractCode = (raw) => {
  if (!raw) return { code: null, rawMessage: "" };
  const m = raw.match(/\(#(\d+)\)\s*(.*)/);
  if (m) return { code: Number(m[1]), rawMessage: m[2] };
  return { code: null, rawMessage: String(raw) };
};

// Public API: pass either a code (number/string), the raw Meta string, or both.
// Always returns { title, body, actionLabel?, actionHref?, code? }.
export const translateWhatsappError = ({ code, rawMessage } = {}) => {
  let resolvedCode = code != null ? Number(code) : null;
  let extra = rawMessage || "";

  if (!resolvedCode && rawMessage) {
    const parsed = extractCode(rawMessage);
    resolvedCode = parsed.code;
    extra = parsed.rawMessage;
  }

  if (resolvedCode && TRANSLATIONS[resolvedCode]) {
    return { code: resolvedCode, ...TRANSLATIONS[resolvedCode] };
  }
  return {
    code: resolvedCode,
    title: I18n.t("whatsapp_error_messages.message_couldn_t_be_sent"),
    body: extra || rawMessage || "WhatsApp returned an error.",
  };
};

export default translateWhatsappError;

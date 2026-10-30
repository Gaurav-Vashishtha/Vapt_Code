const BASE = "/api/whatsapp/inbox";

const queryString = (params = {}) => {
  const qs = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value === undefined || value === null || value === "") return;
    qs.set(key, String(value));
  });
  const out = qs.toString();
  return out ? `?${out}` : "";
};

export const request = async (path, options = {}, attempt = 0) => {
  const { method = "GET", body, form, signal } = options;
  const token = await shopify.idToken();
  const headers = { Authorization: `Bearer ${token}` };
  let payload;
  if (form) {
    payload = form;
  } else if (body) {
    headers["Content-Type"] = "application/json";
    payload = JSON.stringify(body);
  }
  const res = await fetch(`https://${process.env.APP_HOST}${path}`, { method, headers, body: payload, signal });
  const data = await res.json().catch(() => ({}));
  // App Bridge can hand back a token that expired while the tab slept; a second call gets a fresh one.
  if (res.status === 401 && attempt === 0) return request(path, options, 1);
  if (!res.ok) {
    throw Object.assign(new Error(data?.error || `Request failed (${res.status})`), {
      status: res.status,
      code: data?.code,
      metaCode: data?.meta_code,
    });
  }
  return data;
};

export const isAbort = (error) => error?.name === "AbortError";

export const mediaUrl = (url) => {
  if (!url) return null;
  return url.startsWith("/") ? `https://${process.env.APP_HOST}${url}` : url;
};

const conv = (id) => `${BASE}/conversations/${id}`;

export const inboxApi = {
  summary: (opts) => request(`${BASE}/summary`, opts),
  me: () => request(`${BASE}/me`),
  agents: () => request(`${BASE}/agents`),
  reports: () => request(`${BASE}/reports`),
  conversations: (params, opts) => request(`${BASE}/conversations${queryString(params)}`, opts),
  conversation: (id, opts) => request(conv(id), opts),
  updateConversation: (id, patch) => request(conv(id), { method: "PATCH", body: patch }),
  markRead: (id) => request(`${conv(id)}/read`, { method: "POST" }),
  markUnread: (id) => request(`${conv(id)}/unread`, { method: "POST" }),
  block: (id) => request(`${conv(id)}/block`, { method: "POST" }),
  unblock: (id) => request(`${conv(id)}/unblock`, { method: "POST" }),
  messages: (id, params, opts) => request(`${conv(id)}/messages${queryString(params)}`, opts),
  sendText: (id, { text, replyToMessageId, resolve }) =>
    request(`${conv(id)}/messages`, {
      method: "POST",
      body: { type: "text", text, reply_to_message_id: replyToMessageId || undefined, resolve: !!resolve },
    }),
  sendMedia: (id, { file, caption, resolve }) => {
    const form = new FormData();
    form.append("type", "media");
    form.append("file", file);
    if (caption) form.append("caption", caption);
    form.append("resolve", resolve ? "true" : "false");
    return request(`${conv(id)}/messages`, { method: "POST", form });
  },
  sendTemplate: (id, { templateId, bodyParameters, resolve }) =>
    request(`${conv(id)}/messages`, {
      method: "POST",
      body: { type: "template", template_id: templateId, body_parameters: bodyParameters, resolve: !!resolve },
    }),
  customer: (id, opts) => request(`${conv(id)}/customer`, opts),
  sendPaymentLink: (id, orderConfirmationId) =>
    request(`${conv(id)}/customer/payment_link`, {
      method: "POST",
      body: { order_confirmation_id: orderConfirmationId },
    }),
  setLabels: (id, labelIds) => request(`${conv(id)}/labels`, { method: "PUT", body: { label_ids: labelIds } }),
  templates: (conversationId) => request(`${BASE}/templates${queryString({ conversation_id: conversationId })}`),
  labels: () => request(`${BASE}/labels`),
  savedReplies: () => request(`${BASE}/saved_replies`),
  savedReplyUsed: (id) => request(`${BASE}/saved_replies/${id}/used`, { method: "POST" }),
};

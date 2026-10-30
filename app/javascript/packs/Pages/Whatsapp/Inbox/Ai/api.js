import { request } from "../api";

const BASE = "/api/whatsapp/ai";
const conv = (id) => `/api/whatsapp/inbox/conversations/${id}/ai`;

export const aiApi = {
  settings: () => request(`${BASE}/settings`),
  saveSettings: (settings) => request(`${BASE}/settings`, { method: "PATCH", body: settings }),
  importKnowledge: () => request(`${BASE}/settings/import_knowledge`, { method: "POST" }),
  wallet: () => request(`${BASE}/wallet`),
  saveWallet: (patch) => request(`${BASE}/wallet`, { method: "PATCH", body: patch }),
  buy: (pack) => request(`${BASE}/recharges`, { method: "POST", body: { pack } }),
  confirmPurchase: (chargeId) => request(`${BASE}/recharges/confirm`, { method: "POST", body: { charge_id: chargeId } }),
  playground: ({ messages, phone, settings }) =>
    request(`${BASE}/playground`, { method: "POST", body: { messages, phone: phone || undefined, settings } }),
  runs: () => request(`${BASE}/runs`),
  suggest: (conversationId) => request(`${conv(conversationId)}/suggest`, { method: "POST" }),
  pause: (conversationId) => request(`${conv(conversationId)}/pause`, { method: "POST" }),
  resume: (conversationId) => request(`${conv(conversationId)}/resume`, { method: "POST" }),
  dismissDraft: (conversationId) => request(`${conv(conversationId)}/dismiss_draft`, { method: "POST" }),
};

export const AI_BASE = "/features/whatsapp/inbox/ai";
export const AI_TABS = ["setup", "knowledge", "test", "credits", "activity"];
export const aiPath = (tab) => (tab && tab !== "setup" ? `${AI_BASE}/${tab}` : AI_BASE);

export const formatCredits = (n) => Number(n || 0).toLocaleString();

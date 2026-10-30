// Raw fetch with the session token. Responses keep the server's snake_case
// keys (unlike Services/Api.js, which camelizes), so read them as such.
export const api = async (path, { method = "GET", body, form } = {}) => {
  const token = await shopify.idToken();
  const headers = { Authorization: `Bearer ${token}` };
  let payload;
  if (form) {
    payload = form;
  } else if (body) {
    headers["Content-Type"] = "application/json";
    payload = JSON.stringify(body);
  }
  const res = await fetch(`https://${process.env.APP_HOST}${path}`, { method, headers, body: payload });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data?.error || `Request failed (${res.status})`);
  return data;
};

// Polls a background CSV import until it is parsed or has failed.
export const waitForImport = async (id, first, tries = 30) => {
  let info = first;
  for (let i = 0; i < tries && !["ready", "failed"].includes(info?.status); i++) {
    await new Promise((r) => setTimeout(r, 1000));
    info = await api(`/api/whatsapp/audience_imports/${id}`);
  }
  return info;
};

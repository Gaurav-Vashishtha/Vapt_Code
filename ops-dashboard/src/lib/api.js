export async function fetchOverview(from, to, signal) {
  const qs = new URLSearchParams({ from, to });
  const res = await fetch(`/codk-ops/api/overview?${qs}`, { headers: { Accept: 'application/json' }, signal });
  if (!res.ok) throw new Error(res.status === 429 ? 'Too many requests, wait a minute.' : `Request failed (${res.status})`);
  return res.json();
}

export async function fetchCustomerSync(signal) {
  const res = await fetch('/codk-ops/api/customer-sync', { headers: { Accept: 'application/json' }, signal });
  if (!res.ok) throw new Error(`Request failed (${res.status})`);
  return res.json();
}

export async function setCustomerSyncMode(mode, reason) {
  const res = await fetch('/codk-ops/api/customer-sync/mode', {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json', 'X-Ops-Action': '1' },
    body: JSON.stringify({ mode, reason })
  });
  if (!res.ok) throw new Error(`Request failed (${res.status})`);
  return res.json();
}

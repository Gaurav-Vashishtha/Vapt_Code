export async function fetchOverview(from, to, signal) {
  const qs = new URLSearchParams({ from, to });
  const res = await fetch(`/codk-ops/api/overview?${qs}`, { headers: { Accept: 'application/json' }, signal });
  if (!res.ok) throw new Error(res.status === 429 ? 'Too many requests, wait a minute.' : `Request failed (${res.status})`);
  return res.json();
}

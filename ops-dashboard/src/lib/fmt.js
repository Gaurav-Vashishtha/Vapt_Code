const inrCompact = new Intl.NumberFormat('en-IN', { notation: 'compact', maximumFractionDigits: 2 });
const inrFull = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 });
const int = new Intl.NumberFormat('en-IN');

export const num = (n) => int.format(Math.round(n ?? 0));
export const inr = (n) => '₹' + inrCompact.format(n ?? 0);
export const inrExact = (n) => '₹' + inrFull.format(n ?? 0);
export const usd = (n, digits = 0) =>
  (n < 0 ? '-' : '') + '$' + Math.abs(n ?? 0).toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits });

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export const shortDate = (iso) => {
  const [, m, d] = iso.split('-');
  return `${Number(d)} ${MONTHS[Number(m) - 1]}`;
};
export const dateTime = (iso) =>
  iso ? new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }) : '—';

export const isoDate = (d) => {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
};

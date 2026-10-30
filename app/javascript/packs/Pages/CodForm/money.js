/* Money helpers. Every amount that crosses the API is an integer:
   amount × 100 in the shop / presentment currency, also for zero-decimal
   currencies (ARCHITECTURE 0.1). Inputs show plain decimals. */

export const centsToInput = (cents) => {
  if (cents === null || cents === undefined || cents === "") return "";
  const number = Number(cents);
  if (Number.isNaN(number)) return "";
  const amount = number / 100;
  return Number.isInteger(amount) ? String(amount) : amount.toFixed(2);
};

export const inputToCents = (input) => {
  if (input === null || input === undefined) return null;
  const text = String(input).trim().replace(",", ".");
  if (text === "") return null;
  const number = Number(text);
  if (Number.isNaN(number) || number < 0) return null;
  return Math.round(number * 100);
};

const formatAmount = (amount, { decimals, thousands, decimalMark }) => {
  const fixed = amount.toFixed(decimals);
  const [whole, fraction] = fixed.split(".");
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, thousands);
  return fraction ? `${grouped}${decimalMark}${fraction}` : grouped;
};

const FORMATS = {
  amount: { decimals: 2, thousands: ",", decimalMark: "." },
  amount_no_decimals: { decimals: 0, thousands: ",", decimalMark: "." },
  amount_with_comma_separator: { decimals: 2, thousands: ".", decimalMark: "," },
  amount_no_decimals_with_comma_separator: { decimals: 0, thousands: ".", decimalMark: "," },
  amount_with_apostrophe_separator: { decimals: 2, thousands: "'", decimalMark: "." },
  amount_no_decimals_with_space_separator: { decimals: 0, thousands: " ", decimalMark: "," },
  amount_with_space_separator: { decimals: 2, thousands: " ", decimalMark: "," },
  amount_with_period_and_space_separator: { decimals: 2, thousands: " ", decimalMark: "." },
};

/** Format cents with a Shopify money format ("{{amount}} Ft"), else "12.50 HUF". */
export const formatMoney = (cents, moneyFormat, currency) => {
  if (cents === null || cents === undefined || Number.isNaN(Number(cents))) return "";
  const amount = Number(cents) / 100;
  const format = typeof moneyFormat === "string" ? moneyFormat : "";
  const match = /\{\{\s*(\w+)\s*\}\}/.exec(format);
  if (match) {
    const rule = FORMATS[match[1]] || FORMATS.amount;
    const text = format.replace(match[0], formatAmount(amount, rule));
    // Shop formats may carry markup (<span class=money>); show text only.
    return text.replace(/<[^>]*>/g, "");
  }
  const plain = formatAmount(amount, FORMATS.amount);
  return currency ? `${plain} ${currency}` : plain;
};

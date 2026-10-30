import React, { useState, useEffect } from "react";
import { createRoot } from "react-dom/client";
import useQueryString from "./Hooks/useQueryString";
import useAxios from "axios-hooks";
import I18n from "./i18n-lang";

const t = (key, defaultValue) => I18n.t(key, { defaultValue });

const formatMoney = (currency, amount) => {
  const n = Number(amount);
  if (Number.isNaN(n)) return `${currency} ${amount}`;
  return `${currency} ${n.toLocaleString("en-IN", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
};

const isPositive = (amount) => Number(amount) > 0;

const Chevron = ({ open }) => (
  <svg
    className={`ov-chevron ${open ? "ov-chevron-open" : ""}`}
    width="20"
    height="20"
    viewBox="0 0 20 20"
    fill="none"
  >
    <path
      d="M5 7.5L10 12.5L15 7.5"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
);

const ItemThumb = ({ item }) => (
  <div className="ov-item-thumb">
    {item.image_url ? (
      <img src={item.image_url} alt={item.title} loading="lazy" />
    ) : (
      <span className="ov-item-thumb-placeholder">
        {(item.title || "?").charAt(0).toUpperCase()}
      </span>
    )}
    <span className="ov-item-qty-badge">{item.quantity}</span>
  </div>
);

const LineItemRow = ({ item, currency }) => {
  const unitPrice = item.discounted_unit_price ?? item.original_unit_price;
  const hasDiscount =
    item.original_unit_price &&
    item.discounted_unit_price &&
    Number(item.original_unit_price) > Number(item.discounted_unit_price);
  const lineTotal = Number(unitPrice) * item.quantity;

  return (
    <div className="ov-line-item">
      <ItemThumb item={item} />
      <div className="ov-item-info">
        <div className="ov-item-title">{item.title}</div>
        {item.variant_title && (
          <div className="ov-item-variant">{item.variant_title}</div>
        )}
        <div className="ov-item-unit">
          {item.quantity} × {formatMoney(currency, unitPrice)}
        </div>
      </div>
      <div className="ov-item-price">
        {hasDiscount && (
          <span className="ov-item-price-original">
            {formatMoney(currency, Number(item.original_unit_price) * item.quantity)}
          </span>
        )}
        <span>{formatMoney(currency, lineTotal)}</span>
      </div>
    </div>
  );
};

const PriceRow = ({ label, value, variant }) => (
  <div className={`ov-price-row ${variant ? `ov-price-row-${variant}` : ""}`}>
    <span>{label}</span>
    <span>{value}</span>
  </div>
);

const OrderSummary = ({ summary, currency, fallbackAmount }) => {
  const [open, setOpen] = useState(false);

  // No line items available (API fetch failed or older order) — show amount only
  if (!summary || !summary.line_items || summary.line_items.length === 0) {
    return (
      <div className="ov-card ov-summary">
        <div className="ov-summary-total ov-summary-total-only">
          <span>{t("admin.amount_payable", "Amount payable")}</span>
          <span className="ov-amount">{formatMoney(currency, fallbackAmount)}</span>
        </div>
      </div>
    );
  }

  const items = summary.line_items;
  const itemCount = items.reduce((sum, i) => sum + (i.quantity || 0), 0);
  const total = summary.total ?? fallbackAmount;

  return (
    <div className="ov-card ov-summary">
      <button
        type="button"
        className="ov-summary-header"
        onClick={() => setOpen(!open)}
        aria-expanded={open}
      >
        <div className="ov-summary-header-left">
          {!open && (
            <div className="ov-thumb-stack">
              {items.slice(0, 3).map((item, idx) => (
                <div className="ov-thumb-stack-item" key={idx} style={{ zIndex: 3 - idx }}>
                  {item.image_url ? (
                    <img src={item.image_url} alt="" loading="lazy" />
                  ) : (
                    <span>{(item.title || "?").charAt(0).toUpperCase()}</span>
                  )}
                </div>
              ))}
            </div>
          )}
          <div>
            <div className="ov-summary-title">
              {t("admin.order_summary", "Order summary")}
            </div>
            <div className="ov-summary-subtitle">
              {itemCount} {itemCount === 1 ? t("admin.item", "item") : t("admin.items", "items")}
            </div>
          </div>
        </div>
        <div className="ov-summary-header-right">
          <span className="ov-summary-header-total">{formatMoney(currency, total)}</span>
          <Chevron open={open} />
        </div>
      </button>

      {open && (
        <div className="ov-summary-body">
          <div className="ov-line-items">
            {items.map((item, idx) => (
              <LineItemRow key={idx} item={item} currency={currency} />
            ))}
          </div>

          <div className="ov-price-breakdown">
            {summary.subtotal && (
              <PriceRow
                label={t("admin.subtotal", "Subtotal")}
                value={formatMoney(currency, summary.subtotal)}
              />
            )}
            {isPositive(summary.discount) && (
              <PriceRow
                label={t("admin.discount", "Discount")}
                value={`− ${formatMoney(currency, summary.discount)}`}
                variant="discount"
              />
            )}
            {summary.shipping !== null && summary.shipping !== undefined && (
              <PriceRow
                label={t("admin.shipping", "Shipping")}
                value={
                  isPositive(summary.shipping)
                    ? formatMoney(currency, summary.shipping)
                    : t("admin.free", "Free")
                }
              />
            )}
            {isPositive(summary.tax) && (
              <PriceRow
                label={t("admin.taxes", "Taxes")}
                value={formatMoney(currency, summary.tax)}
              />
            )}
          </div>
        </div>
      )}

      <div className="ov-summary-total">
        <span>{t("admin.amount_payable", "Amount payable")}</span>
        <span className="ov-amount">{formatMoney(currency, total)}</span>
      </div>
    </div>
  );
};

const AddressBlock = ({ address }) => {
  if (!address || !address.lines || address.lines.length === 0) return null;
  return (
    <div className="ov-card ov-address">
      <div className="ov-section-label">
        {t("admin.delivery_address", "Delivery address")}
      </div>
      {address.name && <div className="ov-address-name">{address.name}</div>}
      <div className="ov-address-lines">{address.lines.join(", ")}</div>
    </div>
  );
};

const StatusPanel = ({ type, title, message }) => (
  <div className={`ov-status ov-status-${type}`}>
    <div className="ov-status-icon">
      {type === "success" ? (
        <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
          <circle cx="14" cy="14" r="13" stroke="currentColor" strokeWidth="2" />
          <path
            d="M8.5 14.5L12 18L19.5 10.5"
            stroke="currentColor"
            strokeWidth="2.2"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      ) : (
        <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
          <circle cx="14" cy="14" r="13" stroke="currentColor" strokeWidth="2" />
          <path
            d="M10 10L18 18M18 10L10 18"
            stroke="currentColor"
            strokeWidth="2.2"
            strokeLinecap="round"
          />
        </svg>
      )}
    </div>
    <div>
      <div className="ov-status-title">{title}</div>
      {message && <div className="ov-status-message">{message}</div>}
    </div>
  </div>
);

const ConfirmButtons = ({ showCancelButton, autoVerify, order, shop, orderSummary }) => {
  const order_id = useQueryString("order_id");
  const otp = useQueryString("code");
  const [error, setError] = useState(false);
  const [cancelled, setCancelled] = useState(false);
  const [confirmed, setConfirmed] = useState(false);

  const [{ loading: confirmLoading }, onConfirm] = useAxios(
    {
      url: `https://${process.env.APP_HOST}/order_confirmations/confirm`,
      method: "POST",
      data: { order_id, otp },
    },
    { manual: true }
  );

  const [{ loading: cancelLoading }, onCancel] = useAxios(
    {
      url: `https://${process.env.APP_HOST}/order_confirmations/cancel`,
      method: "POST",
      data: { order_id, otp },
    },
    { manual: true }
  );

  const onOrderConfirm = () => {
    onConfirm()
      .then((resp) => {
        if (resp.status === 200) {
          if (resp.data.is_test_order) {
            setConfirmed(true);
          } else {
            window.location.href = resp.data.order_status_url;
          }
        } else {
          setError(true);
        }
      })
      .catch(() => setError(true));
  };

  const onOrderCancel = () => {
    onCancel()
      .then((resp) => {
        if (resp.status === 200) {
          setCancelled(true);
        } else {
          setError(true);
        }
      })
      .catch(() => setError(true));
  };

  useEffect(() => {
    if (autoVerify) {
      onOrderConfirm();
    }
  }, [autoVerify]);

  const expiredMessage =
    "Invalid action or link expired - Order is already cancelled or link is expired, Please place new order.";

  if (autoVerify && error) {
    return (
      <div className="ov-page">
        <div className="ov-shell">
          <StatusPanel
            type="error"
            title={t("admin.link_expired", "Link expired")}
            message={expiredMessage}
          />
        </div>
      </div>
    );
  }

  if (autoVerify) {
    return (
      <div className="ov-page">
        <div className="ov-shell ov-shell-centered">
          <div className="ov-spinner" />
          <div className="ov-loading-text">
            {t("admin.verifying_order", "Verifying your order…")}
          </div>
        </div>
      </div>
    );
  }

  const busy = confirmLoading || cancelLoading;
  const finished = cancelled || confirmed;
  const disableBtns = busy || !order || finished;

  return (
    <div className="ov-page">
      <div className="ov-shell">
        <header className="ov-header">
          <div className="ov-store-name">{shop.owner_name}</div>
          <h1 className="ov-title">
            {t("admin.order_verify_title", "Confirm your order")}
          </h1>
          <div className="ov-header-meta">
            <span className="ov-order-badge">#{order.order_number}</span>
            <span className="ov-customer-meta">
              {order.customer_name} · {order.customer_number}
            </span>
          </div>
        </header>

        {error && (
          <StatusPanel
            type="error"
            title={t("admin.something_went_wrong", "Something went wrong")}
            message={expiredMessage}
          />
        )}
        {cancelled && (
          <StatusPanel
            type="error"
            title={t("admin.order_cancelled_title", "Order cancelled")}
            message={t(
              "admin.order_cancelled_message",
              "Your order has been cancelled. If this was a mistake, please place a new order."
            )}
          />
        )}
        {confirmed && (
          <StatusPanel
            type="success"
            title={t("admin.order_confirmed_title", "Order confirmed")}
            message={t(
              "admin.order_confirmed_message",
              "Your order has been verified successfully!"
            )}
          />
        )}

        <OrderSummary
          summary={orderSummary}
          currency={shop.currency}
          fallbackAmount={order.order_amount}
        />

        <AddressBlock address={orderSummary && orderSummary.shipping_address} />

        {!finished && (
          <>
            <div className="ov-cta-hint">
              {t(
                "admin.order_verify_hint",
                "Please confirm your order so we can start processing it."
              )}
            </div>
            <div className="ov-action-bar">
              {showCancelButton && (
                <button
                  type="button"
                  className="ov-btn ov-btn-secondary"
                  disabled={disableBtns}
                  onClick={onOrderCancel}
                >
                  {cancelLoading
                    ? t("admin.processing", "Processing…")
                    : t("admin.cancel_order", "Cancel order")}
                </button>
              )}
              <button
                type="button"
                className="ov-btn ov-btn-primary"
                disabled={disableBtns}
                onClick={onOrderConfirm}
              >
                {confirmLoading
                  ? t("admin.confirming", "Confirming…")
                  : t("admin.confirm_order", "Confirm order")}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
};

const OrderVerify = (props) => {
  if (props.order_not_found || !props.order) {
    return (
      <div className="ov-page">
        <div className="ov-shell">
          <StatusPanel
            type="error"
            title={t("admin.link_expired", "Link expired")}
            message={t(
              "admin.order_not_found_message",
              "We couldn't find this order. The link may have expired or already been used — please place a new order."
            )}
          />
        </div>
      </div>
    );
  }

  return (
    <ConfirmButtons
      shop={props.shop}
      order={props.order}
      orderSummary={props.order_summary}
      showCancelButton={props.show_cancel_button}
      autoVerify={props.auto_verify}
    />
  );
};

const styles = `
.ov-page {
  min-height: 100vh;
  background: #f4f6f8;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
  color: #1a1d21;
  -webkit-font-smoothing: antialiased;
}

.ov-shell {
  max-width: 520px;
  margin: 0 auto;
  padding: 16px 16px 120px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.ov-shell-centered {
  min-height: 100vh;
  align-items: center;
  justify-content: center;
  padding-bottom: 16px;
}

.ov-header {
  padding: 16px 4px 4px;
}

.ov-store-name {
  font-size: 0.8125rem;
  font-weight: 600;
  color: #6b7280;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  margin-bottom: 6px;
}

.ov-title {
  font-size: 1.5rem;
  font-weight: 700;
  line-height: 1.3;
  margin: 0 0 10px;
}

.ov-header-meta {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 10px;
}

.ov-order-badge {
  background: #eaf1ff;
  color: #1d4ed8;
  padding: 4px 10px;
  border-radius: 999px;
  font-weight: 700;
  font-size: 0.875rem;
}

.ov-customer-meta {
  font-size: 0.875rem;
  color: #4b5563;
  font-weight: 500;
}

.ov-card {
  background: #ffffff;
  border: 1px solid #e5e7eb;
  border-radius: 14px;
  overflow: hidden;
}

.ov-summary-header {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 14px 16px;
  background: none;
  border: none;
  cursor: pointer;
  font: inherit;
  color: inherit;
  text-align: left;
}

.ov-summary-header-left {
  display: flex;
  align-items: center;
  gap: 12px;
}

.ov-thumb-stack {
  display: flex;
}

.ov-thumb-stack-item {
  width: 40px;
  height: 40px;
  border-radius: 10px;
  border: 2px solid #ffffff;
  background: #f3f4f6;
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  color: #9ca3af;
  position: relative;
}

.ov-thumb-stack-item + .ov-thumb-stack-item {
  margin-left: -14px;
}

.ov-thumb-stack-item img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.ov-summary-title {
  font-weight: 700;
  font-size: 0.9375rem;
}

.ov-summary-subtitle {
  font-size: 0.8125rem;
  color: #6b7280;
}

.ov-summary-header-right {
  display: flex;
  align-items: center;
  gap: 6px;
}

.ov-summary-header-total {
  font-weight: 700;
  font-size: 0.9375rem;
}

.ov-chevron {
  color: #6b7280;
  transition: transform 0.18s ease;
}

.ov-chevron-open {
  transform: rotate(180deg);
}

.ov-summary-body {
  border-top: 1px solid #f0f1f3;
}

.ov-line-items {
  padding: 4px 16px;
  max-height: 280px;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
}

.ov-line-item {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 12px 0;
}

.ov-line-item + .ov-line-item {
  border-top: 1px solid #f0f1f3;
}

.ov-item-thumb {
  position: relative;
  width: 52px;
  height: 52px;
  border-radius: 10px;
  background: #f3f4f6;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
}

.ov-item-thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 10px;
}

.ov-item-thumb-placeholder {
  font-weight: 700;
  color: #9ca3af;
  font-size: 1.125rem;
}

.ov-item-qty-badge {
  position: absolute;
  top: -6px;
  right: -6px;
  min-width: 20px;
  height: 20px;
  padding: 0 5px;
  border-radius: 999px;
  background: #374151;
  color: #ffffff;
  font-size: 0.6875rem;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
}

.ov-item-info {
  flex: 1;
  min-width: 0;
}

.ov-item-title {
  font-size: 0.875rem;
  font-weight: 600;
  line-height: 1.35;
}

.ov-item-variant {
  font-size: 0.8125rem;
  color: #6b7280;
  margin-top: 2px;
}

.ov-item-unit {
  font-size: 0.8125rem;
  color: #6b7280;
  margin-top: 4px;
}

.ov-item-price {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 2px;
  font-size: 0.875rem;
  font-weight: 600;
  white-space: nowrap;
}

.ov-item-price-original {
  color: #9ca3af;
  text-decoration: line-through;
  font-weight: 500;
  font-size: 0.8125rem;
}

.ov-price-breakdown {
  border-top: 1px solid #f0f1f3;
  padding: 12px 16px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.ov-price-row {
  display: flex;
  justify-content: space-between;
  font-size: 0.875rem;
  color: #4b5563;
}

.ov-price-row span:last-child {
  font-weight: 600;
  color: #1a1d21;
}

.ov-price-row-discount span:last-child {
  color: #059669;
}

.ov-summary-total {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 14px 16px;
  border-top: 1px solid #f0f1f3;
  background: #fafbfc;
  font-weight: 600;
  font-size: 0.9375rem;
}

.ov-summary-total-only {
  border-top: none;
}

.ov-amount {
  font-size: 1.25rem;
  font-weight: 800;
  color: #1d4ed8;
}

.ov-address {
  padding: 14px 16px;
}

.ov-section-label {
  font-size: 0.75rem;
  font-weight: 700;
  color: #6b7280;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  margin-bottom: 8px;
}

.ov-address-name {
  font-weight: 600;
  font-size: 0.9375rem;
  margin-bottom: 2px;
}

.ov-address-lines {
  font-size: 0.875rem;
  color: #4b5563;
  line-height: 1.5;
}

.ov-cta-hint {
  font-size: 0.8125rem;
  color: #6b7280;
  text-align: center;
  padding: 0 8px;
}

.ov-action-bar {
  display: flex;
  gap: 10px;
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  padding: 12px 16px calc(12px + env(safe-area-inset-bottom));
  background: #ffffff;
  border-top: 1px solid #e5e7eb;
  box-shadow: 0 -4px 16px rgba(17, 24, 39, 0.06);
  z-index: 10;
}

.ov-btn {
  flex: 1;
  min-height: 50px;
  padding: 12px 18px;
  border: none;
  border-radius: 12px;
  font-size: 1rem;
  font-weight: 700;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.15s ease, border-color 0.15s ease, transform 0.05s ease;
}

.ov-btn:active:not(:disabled) {
  transform: scale(0.985);
}

.ov-btn:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.ov-btn-primary {
  flex: 1.4;
  background: #1d4ed8;
  color: #ffffff;
}

.ov-btn-primary:hover:not(:disabled) {
  background: #1e40af;
}

.ov-btn-secondary {
  background: #ffffff;
  color: #4b5563;
  border: 1.5px solid #d1d5db;
}

.ov-btn-secondary:hover:not(:disabled) {
  background: #f9fafb;
  border-color: #9ca3af;
}

.ov-status {
  display: flex;
  gap: 12px;
  align-items: flex-start;
  padding: 16px;
  border-radius: 14px;
  border: 1px solid;
}

.ov-status-success {
  background: #ecfdf5;
  border-color: #a7f3d0;
  color: #065f46;
}

.ov-status-error {
  background: #fef2f2;
  border-color: #fecaca;
  color: #991b1b;
}

.ov-status-icon {
  flex-shrink: 0;
  margin-top: 1px;
}

.ov-status-title {
  font-weight: 700;
  font-size: 0.9375rem;
}

.ov-status-message {
  font-size: 0.875rem;
  margin-top: 3px;
  line-height: 1.5;
}

.ov-spinner {
  border: 4px solid rgba(29, 78, 216, 0.12);
  border-top-color: #1d4ed8;
  width: 44px;
  height: 44px;
  border-radius: 50%;
  animation: ov-spin 0.8s linear infinite;
}

.ov-loading-text {
  margin-top: 14px;
  font-size: 0.9375rem;
  color: #4b5563;
  font-weight: 500;
}

@keyframes ov-spin {
  to { transform: rotate(360deg); }
}

@media (min-width: 768px) {
  .ov-shell {
    padding: 40px 24px 48px;
    gap: 14px;
  }

  .ov-header {
    padding: 0 4px 8px;
  }

  .ov-title {
    font-size: 1.75rem;
  }

  .ov-card {
    border-radius: 16px;
    box-shadow: 0 1px 3px rgba(17, 24, 39, 0.05);
  }

  .ov-action-bar {
    position: static;
    padding: 8px 0 0;
    background: none;
    border-top: none;
    box-shadow: none;
  }

  .ov-amount {
    font-size: 1.375rem;
  }
}
`;

document.addEventListener("DOMContentLoaded", () => {
  const node = document.getElementById("order-verify-react");
  if (!node) return;

  const styleElement = document.createElement("style");
  styleElement.innerHTML = styles;
  document.head.appendChild(styleElement);

  const data = JSON.parse(node.getAttribute("data"));
  const root = createRoot(node);
  root.render(<OrderVerify {...data} />);
});

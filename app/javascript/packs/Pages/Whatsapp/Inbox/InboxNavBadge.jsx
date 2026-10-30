import { useCallback, useState } from "react";
import I18n from "../../../i18n-lang";
import usePolling from "./usePolling";
import { inboxApi, isAbort } from "./api";
import { INBOX_BASE, UNREAD_EVENT } from "./format";

const POLL_MS = 30000;

const applyNavLabel = (count) => {
  const link = document.querySelector(`ui-nav-menu a[data-nav-base="${INBOX_BASE}"]`);
  if (!link) return;
  const label = I18n.t("nav.inbox", { defaultValue: "Inbox" });
  const text = count > 0 ? `${label} (${count})` : label;
  if (link.textContent !== text) link.textContent = text;
};

const InboxNavBadge = () => {
  const [enabled, setEnabled] = useState(true);
  const [pollMs, setPollMs] = useState(POLL_MS);

  const poll = useCallback(async (signal) => {
    try {
      const summary = await inboxApi.summary({ signal });
      const count = Number(summary?.unread_conversations || 0);
      applyNavLabel(count);
      window.dispatchEvent(new CustomEvent(UNREAD_EVENT, { detail: count }));
      if (summary?.poll_seconds) setPollMs(Math.max(10, Number(summary.poll_seconds)) * 1000);
      if (summary && summary.enabled === false) setEnabled(false);
    } catch (e) {
      if (isAbort(e)) return;
      if (e?.status === 404) setEnabled(false);
    }
  }, []);

  usePolling(poll, pollMs, [], { enabled });
  return null;
};

export default InboxNavBadge;

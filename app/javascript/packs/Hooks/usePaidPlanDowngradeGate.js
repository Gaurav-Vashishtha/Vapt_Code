import { useContext, useEffect, useMemo, useState } from "react";
import { StoreContext } from "../Context/Store";
import Api from "../Services/Api";
import {
  collectPaidPlanDowngradeBlockerKeys,
  isPaidPlanSubscriber,
} from "../utils/paidPlanDowngradeBlockers";

/**
 * Fetches COD show/hide status once for paid shops and derives downgrade blockers.
 */
export function usePaidPlanDowngradeGate() {
  const {
    shop: [shop],
    plan: [plan],
    setting: [setting],
  } = useContext(StoreContext);

  const [codShowHideEnabled, setCodShowHideEnabled] = useState(false);
  const [partialRuleSets, setPartialRuleSets] = useState([]);
  const [whatsappNotificationsActive, setWhatsappNotificationsActive] = useState(false);

  const isPaidSubscriber = useMemo(
    () => isPaidPlanSubscriber(plan, shop),
    [plan, shop],
  );

  useEffect(() => {
    if (!isPaidSubscriber || !shop?.id) {
      setCodShowHideEnabled(false);
      return undefined;
    }

    let cancelled = false;
    Api.get("/settings/is_cod_show_hide_enabled")
      .then((response) => {
        const enabled =
          response?.data?.isCodShowHideEnabled ??
          response?.data?.data?.isCodShowHideEnabled ??
          false;
        if (!cancelled) setCodShowHideEnabled(!!enabled);
      })
      .catch(() => {
        if (!cancelled) setCodShowHideEnabled(false);
      });

    return () => {
      cancelled = true;
    };
  }, [isPaidSubscriber, shop?.id]);

  useEffect(() => {
    if (!isPaidSubscriber || !shop?.id) {
      setPartialRuleSets([]);
      return undefined;
    }

    let cancelled = false;
    Api.get("/partial_rule_sets")
      .then((response) => {
        const list = Array.isArray(response?.data) ? response.data : [];
        if (!cancelled) setPartialRuleSets(list);
      })
      .catch(() => {
        if (!cancelled) setPartialRuleSets([]);
      });

    return () => {
      cancelled = true;
    };
  }, [isPaidSubscriber, shop?.id]);

  useEffect(() => {
    if (!isPaidSubscriber || !shop?.id) {
      setWhatsappNotificationsActive(false);
      return undefined;
    }

    let cancelled = false;
    Api.get("/api/whatsapp/template_bindings/notifications_active")
      .then((response) => {
        const active =
          response?.data?.active ?? response?.data?.data?.active ?? false;
        if (!cancelled) setWhatsappNotificationsActive(!!active);
      })
      .catch(() => {
        if (!cancelled) setWhatsappNotificationsActive(false);
      });

    return () => {
      cancelled = true;
    };
  }, [isPaidSubscriber, shop?.id]);

  const blockerKeys = useMemo(
    () =>
      collectPaidPlanDowngradeBlockerKeys(
        setting,
        codShowHideEnabled,
        partialRuleSets,
        whatsappNotificationsActive,
      ),
    [setting, codShowHideEnabled, partialRuleSets, whatsappNotificationsActive],
  );

  const downgradeBlocked = isPaidSubscriber && blockerKeys.length > 0;

  return {
    isPaidSubscriber,
    codShowHideEnabled,
    blockerKeys,
    downgradeBlocked,
  };
}

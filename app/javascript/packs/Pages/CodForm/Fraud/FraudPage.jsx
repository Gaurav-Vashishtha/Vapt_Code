import React, { useCallback } from "react";
import { codFormApi } from "../api";
import useResource from "../useResource";
import { DEFAULT_FRAUD, DEFAULT_GENERAL } from "../defaults";
import { mergeDefaults, setIn } from "../utils";
import { t } from "../i18n";
import Screen, { SaveErrorBanner } from "../components/Screen";
import ScreenSaveBar from "../components/ScreenSaveBar";
import BlockListCard from "./BlockListCard";
import LimitsCard from "./LimitsCard";
import MaxQuantityCard from "./MaxQuantityCard";
import RtoGatingCard from "./RtoGatingCard";
import BlockedAttemptsTable from "./BlockedAttemptsTable";

const prepare = (raw) => ({
  fraud: mergeDefaults(DEFAULT_FRAUD, (raw && raw.fraud) || {}),
  otp: mergeDefaults(DEFAULT_GENERAL.otp, (raw && raw.otp) || {}),
  rto: mergeDefaults(DEFAULT_GENERAL.rto, (raw && raw.rto) || {}),
  shop_otp_enabled: !!(raw && raw.shop_otp_enabled),
});

/** /features/cod-form/fraud — block lists, limits, maximum quantity, RTO gating, blocked attempts (OTP lives on Setup). */
const FraudPage = () => {
  const { data, setData, isDirty, loading, saving, error, saveError, save, discard, reload, clearSaveError } = useResource({
    load: () => codFormApi.fraud.show(),
    // OTP is edited on Setup now; not sending it here keeps the two screens from overwriting each other.
    save: (current) => codFormApi.fraud.update({ fraud: current.fraud, rto: current.rto }),
    prepare,
  });

  const change = useCallback((path, value) => setData((current) => setIn(current, path, value)), [setData]);

  return (
    <Screen
      title={t("fraud.title", "Fraud protection")}
      subtitle={t("fraud.subtitle", "Keep fake and repeat COD orders out of the form.")}
      loading={loading || !data}
      error={error}
      onRetry={reload}
      skeletonCards={4}
    >
      {data && (
        <>
          <ScreenSaveBar open={isDirty} saving={saving} onSave={save} onDiscard={discard} />
          <SaveErrorBanner error={saveError} onDismiss={clearSaveError} />
          <BlockListCard fraud={data.fraud} onChange={change} />
          <LimitsCard fraud={data.fraud} onChange={change} />
          <MaxQuantityCard fraud={data.fraud} onChange={change} />
          <RtoGatingCard rto={data.rto} onChange={change} />
          <BlockedAttemptsTable />
        </>
      )}
    </Screen>
  );
};

export default FraudPage;

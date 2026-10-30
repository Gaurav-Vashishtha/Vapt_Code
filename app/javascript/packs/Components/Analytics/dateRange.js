import I18n from "../../i18n-lang";

export const DEFAULT_DAYS = "7";

export const dayOptions = () => [
  { label: I18n.t("summary.days_options.today", { defaultValue: "Today" }), value: "1" },
  { label: I18n.t("summary.days_options.last_7_days"), value: "7" },
  { label: I18n.t("summary.days_options.last_15_days"), value: "15" },
  { label: I18n.t("summary.days_options.last_30_days"), value: "30" },
  { label: I18n.t("summary.days_options.last_90_days"), value: "90" },
];

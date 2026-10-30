import React from "react";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import CountryMultiSelect from "../components/CountryMultiSelect";
import { t } from "../i18n";

/** Enabled countries (VIS-3). An empty list means every country. */
const CountriesCard = ({ general, onChange }) => (
  <SectionCard
    title={t("setup.countries_title", "Countries")}
    description={t("setup.countries_help", "The COD button is shown to buyers in these countries. Buyers elsewhere get your normal checkout.")}
  >
    <CountryMultiSelect
      label={t("setup.countries_label", "Enabled countries")}
      value={general.countries}
      onChange={(codes) => onChange(["countries"], codes)}
      emptyText={t("setup.countries_all", "No country selected: the form is available in every country.")}
    />
  </SectionCard>
);

export default CountriesCard;

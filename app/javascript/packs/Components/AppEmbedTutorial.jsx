import React from "react";
import I18n from "../i18n-lang";
import EmbedTutorial from "../Pages/CodForm/components/EmbedTutorial";

const tt = (key, defaultValue, vars) => I18n.t(`app_embed_tutorial.${key}`, { defaultValue, ...(vars || {}) });

/**
 * The animated theme-editor walkthrough (switch, then a zoom on Save) for the "COD King OTP
 * Block" app embed that pre-order OTP and partial payment need. Same picture as the COD Form
 * embed step, so every app embed screen teaches the Save click the same way. `buttonLabel` is
 * the label of the screen's own "open the theme editor" button, quoted in step 1.
 */
const AppEmbedTutorial = ({ embedName = "COD King OTP Block", buttonLabel }) => (
  <EmbedTutorial
    embedName={embedName}
    alt={tt("alt", "In the theme editor: turn on the COD King OTP Block switch under App embeds, then click Save at the top right.")}
    labels={{
      save: tt("save", "Save"),
      appEmbeds: tt("app_embeds", "App embeds"),
      otherApp: tt("other_app", "Other app"),
    }}
    steps={[
      tt("step_open", "Click %{button}. The theme editor opens in a new tab.", {
        button: buttonLabel || I18n.t("pre_order.enable", { defaultValue: "Enable" }),
      }),
      tt("step_switch", "Under App embeds, turn on the \"COD King OTP Block\" switch."),
      tt("step_save", "Click Save at the top right. Without Save, nothing is switched on."),
      tt("step_back", "Come back to this tab. We detect it automatically."),
    ]}
  />
);

export default AppEmbedTutorial;

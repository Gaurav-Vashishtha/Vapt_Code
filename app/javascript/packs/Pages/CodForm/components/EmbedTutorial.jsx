import React, { useEffect, useState } from "react";
import { BlockStack, InlineStack, Text } from "@shopify/polaris";
import { t } from "../i18n";

const STEP_MS = 3200;
const CSS = `
.codk-tut{position:relative;width:100%;max-width:520px;aspect-ratio:16/9;border:1px solid #d4d4d8;border-radius:10px;overflow:hidden;background:#f4f4f5;font-family:inherit}
.codk-tut-stage{position:absolute;inset:0;transform-origin:100% 0;transition:transform .9s cubic-bezier(.3,.7,.2,1)}
.codk-tut[data-step="2"] .codk-tut-stage{transform:scale(2.6)}
.codk-tut-bar{position:absolute;top:0;left:0;right:0;height:13%;background:#fff;border-bottom:1px solid #e4e4e7;display:flex;align-items:center;justify-content:space-between;padding:0 3%}
.codk-tut-dots{display:flex;gap:4px}
.codk-tut-dots i{width:7px;height:7px;border-radius:50%;background:#d4d4d8;display:block}
.codk-tut-save{position:relative;background:#1f2937;color:#fff;font-size:10px;font-weight:700;line-height:1;padding:5px 12px;border-radius:5px}
.codk-tut-side{position:absolute;top:13%;left:0;bottom:0;width:40%;background:#fff;border-right:1px solid #e4e4e7;padding:4% 3%}
.codk-tut-h{font-size:9px;font-weight:700;color:#3f3f46;margin-bottom:6%}
.codk-tut-row{position:relative;display:flex;align-items:center;justify-content:space-between;gap:6px;padding:5% 4%;border-radius:6px;margin-bottom:4%;font-size:8px;color:#52525b;background:#fafafa}
.codk-tut-row b{font-weight:700;color:#18181b}
.codk-tut-tog{flex:none;width:22px;height:12px;border-radius:99px;background:#d4d4d8;position:relative;transition:background .4s}
.codk-tut-tog::after{content:"";position:absolute;top:2px;left:2px;width:8px;height:8px;border-radius:50%;background:#fff;transition:left .4s}
.codk-tut-tog.on{background:#16a34a}
.codk-tut-tog.on::after{left:12px}
.codk-tut-page{position:absolute;top:13%;left:40%;right:0;bottom:0;padding:5%}
.codk-tut-page i{display:block;border-radius:5px;background:#e4e4e7;margin-bottom:5%}
.codk-tut-ring{position:absolute;inset:-4px;border:2px solid #dc2626;border-radius:8px;opacity:0;pointer-events:none}
.codk-tut[data-step="1"] .codk-tut-row.me .codk-tut-ring,.codk-tut[data-step="2"] .codk-tut-save .codk-tut-ring{opacity:1;animation:codk-tut-pulse 1.1s ease-in-out infinite}
@keyframes codk-tut-pulse{50%{box-shadow:0 0 0 5px rgba(220,38,38,.25)}}
@media (prefers-reduced-motion:reduce){.codk-tut-stage{transition:none}.codk-tut[data-step="2"] .codk-tut-stage{transform:none}.codk-tut-ring{animation:none!important}}
`;

/**
 * A small animated picture of the theme editor (a drawing, not a screenshot) for an app embed
 * step: first the embed's switch, then a zoom on the Save button at the top right, which is the
 * click merchants miss. The numbered steps next to it say the same in words.
 *
 * Defaults to the "COD King – COD Form" embed. Other embeds (the "COD King OTP Block" used by
 * pre-order OTP and partial payment) pass `embedName`, `steps` (four lines: open, switch, save,
 * come back) and `alt` — see Components/AppEmbedTutorial.jsx.
 */
const EmbedTutorial = ({ embedName, steps: customSteps, alt, labels }) => {
  const [step, setStep] = useState(1);
  useEffect(() => {
    const timer = setInterval(() => setStep((current) => (current === 1 ? 2 : 1)), STEP_MS);
    return () => clearInterval(timer);
  }, []);

  const name = embedName || "COD King – COD Form";
  const text = labels || {};
  const steps = customSteps && customSteps.length ? customSteps : [
    t("tutorial.step_open", "Click Open theme editor. It opens in a new tab."),
    t("tutorial.step_switch", "The \"COD King – COD Form\" switch is already turned on for you. If it is grey, click it."),
    t("tutorial.step_save", "Click Save at the top right. Without Save, nothing is switched on."),
    t("tutorial.step_back", "Come back to this tab. We detect it automatically."),
  ];
  // Which numbered line the picture is showing right now.
  const active = step === 1 ? 1 : 2;

  return (
    <BlockStack gap="300">
      <style>{CSS}</style>
      <InlineStack gap="400" blockAlign="center" wrap>
        <div className="codk-tut" data-step={step} role="img" aria-label={alt || t("tutorial.alt", "In the theme editor: check the COD King – COD Form switch is on, then click Save at the top right.")}>
          <div className="codk-tut-stage">
            <div className="codk-tut-bar">
              <span className="codk-tut-dots"><i /><i /><i /></span>
              <span className="codk-tut-save">
                {text.save || t("tutorial.save", "Save")}
                <span className="codk-tut-ring" />
              </span>
            </div>
            <div className="codk-tut-side">
              <div className="codk-tut-h">{text.appEmbeds || t("tutorial.app_embeds", "App embeds")}</div>
              <div className="codk-tut-row me">
                <span><b>{name}</b></span>
                <span className="codk-tut-tog on" />
                <span className="codk-tut-ring" />
              </div>
              <div className="codk-tut-row">
                <span>{text.otherApp || t("tutorial.other_embed", "Other app")}</span>
                <span className="codk-tut-tog" />
              </div>
            </div>
            <div className="codk-tut-page">
              <i style={{ height: "38%" }} />
              <i style={{ height: "12%", width: "70%" }} />
              <i style={{ height: "12%", width: "45%" }} />
            </div>
          </div>
        </div>
        <div style={{ flex: "1 1 220px", minWidth: 0 }}>
          <BlockStack gap="200">
            {steps.map((label, index) => (
              <InlineStack key={index} gap="200" blockAlign="start" wrap={false}>
                <span
                  style={{
                    flex: "0 0 auto",
                    width: 22,
                    height: 22,
                    borderRadius: "50%",
                    display: "inline-flex",
                    alignItems: "center",
                    justifyContent: "center",
                    fontSize: 12,
                    fontWeight: 700,
                    background: index === active ? "#dc2626" : "#e4e4e7",
                    color: index === active ? "#fff" : "#3f3f46",
                    transition: "background .3s",
                  }}
                >
                  {index + 1}
                </span>
                <Text as="span" variant="bodyMd" fontWeight={index === active ? "semibold" : "regular"}>
                  {label}
                </Text>
              </InlineStack>
            ))}
          </BlockStack>
        </div>
      </InlineStack>
    </BlockStack>
  );
};

export default EmbedTutorial;

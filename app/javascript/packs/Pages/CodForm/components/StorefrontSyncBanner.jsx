import React, { useCallback, useEffect, useRef, useState } from "react";
import { Banner, List } from "@shopify/polaris";
import { codFormApi, SAVED_EVENT } from "../api";
import { t } from "../i18n";

const AFTER_SAVE_MS = 500;

/**
 * Saving publishes, so this bar is normally invisible. It only appears when something
 * saved did not reach the storefront (the store could not be updated, or a form has a
 * setting that needs fixing), and offers to publish again.
 */
const StorefrontSyncBanner = () => {
  const [state, setState] = useState(null);
  const [publishing, setPublishing] = useState(false);
  const [problem, setProblem] = useState(null);
  const alive = useRef(true);

  const check = useCallback(() => {
    codFormApi.sync.show().then(
      (sync) => alive.current && sync && setState(sync),
      () => {},
    );
  }, []);

  useEffect(() => {
    alive.current = true;
    const timers = [];
    const onSaved = () => timers.push(setTimeout(check, AFTER_SAVE_MS));
    check();
    window.addEventListener(SAVED_EVENT, onSaved);
    return () => {
      alive.current = false;
      timers.forEach(clearTimeout);
      window.removeEventListener(SAVED_EVENT, onSaved);
    };
  }, [check]);

  const publish = () => {
    setPublishing(true);
    setProblem(null);
    codFormApi.sync
      .publish()
      .then(
        (sync) => {
          if (!alive.current) return;
          if (sync) setState(sync);
          const errors = (sync && sync.form_errors) || [];
          if (errors.length) setProblem({ forms: errors });
          else if (!sync || sync.status === "failed") setProblem({});
          else if (window.shopify && window.shopify.toast) window.shopify.toast.show(t("common.resync_done", "Settings synced to your storefront"));
        },
        () => alive.current && setProblem({}),
      )
      .then(() => alive.current && setPublishing(false));
  };

  if (!state || (state.live && !problem)) return null;
  const forms = (problem && problem.forms) || state.forms || [];
  return (
    <Banner
      tone={problem ? "critical" : "warning"}
      title={t("common.sync_not_synced_title", "Your settings are not synced to your storefront")}
      action={{ content: t("common.resync_now", "Resync now"), onAction: publish, loading: publishing }}
    >
      {forms.length > 0 ? (
        <List type="bullet">
          {forms.map((form) => (
            <List.Item key={form.id}>
              {t("common.sync_form_needs_fix", "Form “%{name}” has a setting that needs fixing in the form designer", { name: form.name })}
            </List.Item>
          ))}
        </List>
      ) : (
        <p>{t("common.sync_failed_body", "Your store could not be updated. Try again in a moment.")}</p>
      )}
    </Banner>
  );
};

export default StorefrontSyncBanner;

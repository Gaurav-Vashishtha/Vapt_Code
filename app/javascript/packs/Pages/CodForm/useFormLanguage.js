import { useEffect, useState } from "react";
import { codFormApi } from "./api";
import { refreshBootstrap } from "./useCodFormBootstrap";

/**
 * Setup → Form language (general.language), shared by the onboarding language picker and the
 * onboarding form preview so the preview follows the picker straight away.
 * "" = the storefront's language. Loaded once per page; `setFormLanguage` saves it.
 */
let state = { loaded: false, value: "", saving: false, failed: false };
let inflight = null;
const listeners = new Set();

const publish = (next) => {
  state = { ...state, ...next };
  listeners.forEach((listener) => listener(state));
};

const load = () => {
  if (!inflight) {
    inflight = codFormApi.setup
      .show()
      .then((body) => publish({ loaded: true, value: (body && body.general && body.general.language) || "" }))
      .catch(() => {
        inflight = null;
        publish({ loaded: true });
      });
  }
  return inflight;
};

export const setFormLanguage = (value) => {
  const previous = state.value;
  publish({ value, saving: true, failed: false });
  return codFormApi.setup
    .update({ language: value })
    .then((body) => {
      publish({ saving: false, value: (body && body.general && body.general.language) || value });
      refreshBootstrap();
    })
    .catch(() => publish({ saving: false, failed: true, value: previous }));
};

const useFormLanguage = () => {
  const [current, setCurrent] = useState(state);
  useEffect(() => {
    listeners.add(setCurrent);
    if (!state.loaded) load();
    else setCurrent(state);
    return () => listeners.delete(setCurrent);
  }, []);
  return current;
};

export default useFormLanguage;

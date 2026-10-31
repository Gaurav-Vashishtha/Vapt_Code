import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import I18n from "../../i18n-lang";
import { parseError } from "./api";
import { clone, deepEqual } from "./utils";

/**
 * The standard screen pattern (ARCHITECTURE H.3):
 *
 *   const {data, setData, original, isDirty, loading, saving, error, save,
 *          discard, reload} = useResource({
 *     load: () => codFormApi.setup.show(),
 *     save: (d) => codFormApi.setup.update(d.general),
 *   });
 *
 * - `load` resolves to the editable data; `prepare(raw)` may shape it first.
 * - `save(data)` resolves to the saved resource, which becomes the new
 *   `original` (through `prepare`). Return `undefined` to keep `data`.
 * - `isDirty` is a deep comparison with `original`.
 * - `error` is the parsed load error; `saveError` the parsed save error
 *   (422 messages, 402 gate) for the screen to show.
 */
const useResource = ({ load, save, prepare, deps = [], toastOnSave = true }) => {
  const [data, setDataState] = useState(null);
  const [original, setOriginal] = useState(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const [saveError, setSaveError] = useState(null);
  const mounted = useRef(true);
  const dataRef = useRef(null);
  const loadRef = useRef(load);
  const saveRef = useRef(save);
  const prepareRef = useRef(prepare);
  loadRef.current = load;
  saveRef.current = save;
  prepareRef.current = prepare;

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  const accept = useCallback((raw) => {
    const shaped = prepareRef.current ? prepareRef.current(raw) : raw;
    dataRef.current = shaped;
    setDataState(shaped);
    setOriginal(clone(shaped));
    return shaped;
  }, []);

  const reload = useCallback(() => {
    setLoading(true);
    setError(null);
    return Promise.resolve()
      .then(() => loadRef.current())
      .then((raw) => {
        if (mounted.current) accept(raw);
      })
      .catch((err) => {
        if (mounted.current) setError(parseError(err));
      })
      .then(() => {
        if (mounted.current) setLoading(false);
      });
  }, [accept]);

  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  const setData = useCallback((next) => {
    setDataState((previous) => {
      const value = typeof next === "function" ? next(previous) : next;
      dataRef.current = value;
      return value;
    });
  }, []);

  const doSave = useCallback(() => {
    if (!saveRef.current) return Promise.resolve(false);
    setSaving(true);
    setSaveError(null);
    return Promise.resolve()
      .then(() => saveRef.current(dataRef.current))
      .then((raw) => {
        if (!mounted.current) return;
        if (raw === undefined) setOriginal(clone(dataRef.current));
        else accept(raw);
        if (toastOnSave && window.shopify && window.shopify.toast) {
          window.shopify.toast.show(I18n.t("admin.settings_saved"));
        }
      })
      .then(() => true)
      .catch((err) => {
        if (mounted.current) setSaveError(parseError(err));
        return false;
      })
      .then((ok) => {
        if (mounted.current) setSaving(false);
        return ok;
      });
  }, [accept, toastOnSave]);

  const discard = useCallback(() => {
    setSaveError(null);
    setData(clone(original));
  }, [original, setData]);

  const isDirty = useMemo(
    // `original` is a JSON copy, so `data` is compared in the same form: a value JSON cannot
    // carry (undefined, NaN) must never make a freshly loaded screen look edited.
    () => data !== null && original !== null && !deepEqual(clone(data), original),
    [data, original],
  );

  return {
    data,
    setData,
    original,
    isDirty,
    loading,
    saving,
    error,
    saveError,
    clearSaveError: () => setSaveError(null),
    save: doSave,
    discard,
    reload,
    /** Replace both data and original with a fresh server payload (no dirty state). */
    replace: accept,
  };
};

export default useResource;

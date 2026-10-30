import { writable, get } from "svelte/store";
import { getSessionValue } from "../services/sessionService.js";

/**
 * The merchant's settings, as a store.
 *
 * Components used to read these straight out of sessionStorage, which meant
 * each one sampled the settings once when it initialised and never saw them
 * change again — `$: T = createTranslator(getSessionValue("settingSession"))`
 * has no reactive dependency, so it runs exactly once. That is invisible on a
 * storefront, where the settings are fixed for the life of the page, but it
 * makes them impossible to change under a running widget, and it already
 * misrenders whenever the settings land after the first paint.
 *
 * Reading through this store instead fixes both. sessionStorage stays the
 * durable copy — it survives navigation and the plain .js helpers still read it
 * on demand — but the store is what the UI renders from.
 */
export const settingsStore = writable(getSessionValue("settingSession") || null);

/** Current settings for non-reactive callers. */
export const getSettingsSnapshot = () => get(settingsStore);

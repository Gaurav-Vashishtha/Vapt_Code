import { useEffect, useRef } from "react";

const usePolling = (fn, ms, deps = [], { enabled = true, immediate = true } = {}) => {
  const fnRef = useRef(fn);
  fnRef.current = fn;
  const depKey = JSON.stringify(deps);

  useEffect(() => {
    if (!enabled) return undefined;
    let timer = null;
    let cancelled = false;
    let running = false;
    let controller = null;

    const schedule = () => {
      clearTimeout(timer);
      if (!cancelled && !document.hidden) timer = setTimeout(tick, ms);
    };

    const tick = async (force = false) => {
      if (cancelled || running || (!force && document.hidden)) return;
      running = true;
      controller = new AbortController();
      try {
        await fnRef.current(controller.signal);
      } catch (e) {
        // Callers own error display; a failed poll must not stop the chain.
      } finally {
        running = false;
        schedule();
      }
    };

    const onVisibility = () => {
      if (document.hidden) clearTimeout(timer);
      else tick();
    };

    document.addEventListener("visibilitychange", onVisibility);
    // The embedded admin iframe can report hidden during its first paint; the
    // first load must still run or the page sits on a spinner.
    if (immediate) tick(true);
    else schedule();

    return () => {
      cancelled = true;
      clearTimeout(timer);
      if (controller) controller.abort();
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [ms, enabled, depKey]);
};

export default usePolling;

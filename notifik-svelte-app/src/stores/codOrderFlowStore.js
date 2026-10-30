import { writable } from "svelte/store";

const initialState = {
  show: false,
  isProcessing: false,
  orderResult: null,
};

const { subscribe, set, update } = writable(initialState);

export const codOrderFlowStore = {
  subscribe,
  setShow(show) {
    update((s) => ({ ...s, show: !!show }));
  },
  setProcessing(isProcessing) {
    update((s) => ({ ...s, isProcessing: !!isProcessing }));
  },
  setOrderResult(orderResult) {
    update((s) => ({ ...s, orderResult }));
  },
  /** Call when starting COD order (show flow, processing) */
  start() {
    set({
      show: true,
      isProcessing: true,
      orderResult: null,
    });
  },
  /** Call when order API succeeded (stop processing, set result) */
  success(orderResult) {
    update((s) => ({
      ...s,
      isProcessing: false,
      orderResult: orderResult || null,
    }));
  },
  /** Call when order API failed or user dismissed (hide flow) */
  clear() {
    set(initialState);
  },
};

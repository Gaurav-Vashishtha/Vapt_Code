export {};

declare global {
  interface Window {
    Shopify?: {
      shop?: string;
      analytics?: {
        visitor?: (
          payload: { email?: string; phone?: string },
          options: { appId: string },
        ) => boolean;
        [key: string]: unknown;
      };
      [key: string]: unknown;
    };
    ShopifyAnalytics?: {
      meta?: {
        selectedVariantId?: string | number;
      };
    };
    enableNormalCheckout?: () => void;
    codk_isProcessing?: boolean;
    codkScrollY?: number;
  }
}

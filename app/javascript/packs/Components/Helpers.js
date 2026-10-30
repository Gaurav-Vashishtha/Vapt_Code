export const IsPlusShippingPage = () => {
    // actual shopify plus checkout
    if (window?.Shopify?.Checkout?.step === 'shipping_method') {
        return true
    }
    // our regular shopify checkout for testing
    if (window.location?.pathname?.startsWith('/checkouts/') &&
        window.location?.pathname?.includes('/shipping')) {
        return true
    }
    return false
}
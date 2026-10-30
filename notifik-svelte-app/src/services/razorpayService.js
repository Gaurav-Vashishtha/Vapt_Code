/**
 * Razorpay Payment Service
 * 
 * Handles Razorpay Checkout integration for payment processing
 */

/**
 * Load Razorpay Checkout script dynamically
 * @returns {Promise<void>}
 */
export const loadRazorpayScript = () => {
  return new Promise((resolve, reject) => {
    // Check if script is already loaded
    if (window.Razorpay) {

      resolve();
      return;
    }

    // Check if script is already being loaded
    const existingScript = document.querySelector('script[src*="razorpay.com"]');
    if (existingScript) {

      let attempts = 0;
      const maxAttempts = 50; // 5 seconds max wait
      const checkInterval = setInterval(() => {
        attempts++;
        if (window.Razorpay) {
          clearInterval(checkInterval);

          resolve();
        } else if (attempts >= maxAttempts) {
          clearInterval(checkInterval);
          reject(new Error('Razorpay script timeout - took too long to load'));
        }
      }, 100);
      return;
    }

    // Load Razorpay script

    const script = document.createElement('script');
    script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.async = true;
    script.onload = () => {

      resolve();
    };
    script.onerror = (error) => {

      reject(new Error('Failed to load Razorpay script. Please check your internet connection.'));
    };
    document.head.appendChild(script); // Use head instead of body for better loading
  });
};

/**
 * Initialize Razorpay Checkout
 * @param {Object} options - Razorpay options
 * @param {string} options.key - Razorpay key ID
 * @param {string} options.amount - Amount in paise
 * @param {string} options.currency - Currency code
 * @param {string} options.name - Merchant name
 * @param {string} options.description - Order description
 * @param {string} options.order_id - Razorpay order ID
 * @param {Object} options.prefill - Prefill customer details
 * @param {Object} options.handler - Success handler
 * @param {Function} options.onSuccess - Success callback
 * @param {Function} options.onFailure - Failure callback
 * @returns {Object} Razorpay instance
 */
export const initializeRazorpay = async (options) => {
  try {
    await loadRazorpayScript();

    if (!window.Razorpay) {
      throw new Error('Razorpay SDK not loaded');
    }

    // Ensure amount is an integer (Razorpay requires integer in paise)
    const amount = typeof options.amount === 'string' 
      ? parseInt(options.amount, 10) 
      : Math.round(parseFloat(options.amount) || 0);

    // Validate required fields
    if (!options.key) {
      throw new Error('Razorpay key is required');
    }
    if (!options.order_id) {
      throw new Error('Razorpay order_id is required');
    }
    if (!amount || amount <= 0) {
      throw new Error(`Invalid amount: ${options.amount}`);
    }

    // Handler function as per Razorpay docs / Gemini suggestion: Razorpay calls this when payment succeeds.
    // We normalize response (payment_id/order_id/signature or razorpay_*) and pass to onSuccess which calls verify API.
    const handlerFunction = function (response) {
      if (!response || typeof response !== 'object') {

        return;
      }
      // Normalize to Razorpay's standard keys (support both razorpay_* and payment_id/order_id/signature)
      const normalized = {
        razorpay_payment_id: response.razorpay_payment_id || response.razorpayPaymentId || response.payment_id,
        razorpay_order_id: response.razorpay_order_id || response.razorpayOrderId || response.order_id,
        razorpay_signature: response.razorpay_signature || response.razorpaySignature || response.signature
      };

      if (document.body) {
        document.body.style.overflow = '';
      }

      if (options.onSuccess && typeof options.onSuccess === 'function') {
        try {
          options.onSuccess(normalized);

        } catch (error) {

        }
      } else {

      }
    };
    
    // Store handler reference globally for debugging
    window._razorpayHandler = handlerFunction;

    const razorpayOptions = {
      key: options.key,
      amount: amount, // Must be integer in paise
      currency: options.currency || 'INR',
      name: options.name || 'Merchant',
      description: options.description || 'Order Payment',
      order_id: options.order_id, // Must be valid order ID from Razorpay Orders API
      prefill: {
        name: options.prefill?.name || '',
        email: options.prefill?.email || '',
        contact: options.prefill?.contact || ''
      },
      theme: {
        color: '#3399cc'
      },
      handler: handlerFunction, // Use the named function for better debugging
      ...(options.callback_url ? { callback_url: options.callback_url } : {}),
      modal: {
        ondismiss: function () {

          // Restore body overflow if it was hidden
          if (document.body) {
            document.body.style.overflow = '';
          }
          if (options.onFailure && typeof options.onFailure === 'function') {

            options.onFailure(new Error('Payment cancelled by user'));
          }
        }
      }
    };

    // Log the handler function to verify it's set correctly

    // Ensure Razorpay modal appears on top by injecting CSS
    // Razorpay needs to appear above our modal (2147483647) to be visible
    // Note: Razorpay checkout.js always opens its own modal - cannot be embedded in custom container
    const styleId = 'razorpay-z-index-fix';
    if (!document.getElementById(styleId)) {
      const style = document.createElement('style');
      style.id = styleId;
      style.textContent = `
        /* Razorpay modal should appear on top of everything */
        .razorpay-container,
        .razorpay-checkout-frame,
        iframe[src*="razorpay.com"],
        .razorpay-modal,
        [class*="razorpay"] {
          z-index: 2147483648 !important; /* Higher than our modal to appear on top */
        }
        .razorpay-overlay {
          z-index: 2147483647 !important;
        }
        /* Ensure Razorpay modal is visible and functional */
        .razorpay-container iframe {
          z-index: 2147483648 !important;
        }
      `;
      document.head.appendChild(style);
    }

    const razorpay = new window.Razorpay(razorpayOptions);
    
    // Add window-level listener for Razorpay postMessage events (for UPI payments)
    // Razorpay might send messages via postMessage for certain payment methods
    const messageHandler = (event) => {
      if (!event.origin || !event.origin.includes('razorpay.com')) return;
      const data = typeof event.data === 'string' ? (function () { try { return JSON.parse(event.data); } catch (_) { return null; } })() : event.data;
      if (!data || typeof data !== 'object') return;
      // Only act on payment success (handler may not fire in iframe/UPI; postMessage can be a fallback)
      const paymentId = data.razorpay_payment_id || data.payment_id;
      const orderId = data.razorpay_order_id || data.order_id;
      const signature = data.razorpay_signature || data.signature;
      if (paymentId && orderId && signature && options.onSuccess && typeof options.onSuccess === 'function') {

        options.onSuccess({
          razorpay_payment_id: paymentId,
          razorpay_order_id: orderId,
          razorpay_signature: signature
        });
      }
    };
    
    // Add event listener for postMessage
    window.addEventListener('message', messageHandler);

    // Store the message handler on the razorpay instance for cleanup
    razorpay._messageHandler = messageHandler;
    
    return razorpay;
  } catch (error) {

    throw error;
  }
};

/**
 * Open Razorpay payment modal
 * @param {Object} options - Razorpay options
 * @returns {Promise<Object>} Payment response
 */
export const openRazorpayCheckout = async (options) => {
  return new Promise(async (resolve, reject) => {
    let modalOpened = false;
    
    try {

      // Validate required options
      if (!options.key) {
        throw new Error('Razorpay key is missing');
      }
      if (!options.order_id) {
        throw new Error('Razorpay order_id is missing');
      }
      if (!options.amount || options.amount <= 0) {
        throw new Error(`Invalid amount: ${options.amount}`);
      }

      const razorpay = await initializeRazorpay({
        ...options,
        onSuccess: (response) => {

          resolve(response);
        },
        onFailure: (error) => {

          reject(error);
        }
      });

      if (!razorpay) {
        throw new Error('Failed to initialize Razorpay instance');
      }

      if (typeof razorpay.open !== 'function') {
        throw new Error('Razorpay instance does not have open() method');
      }

      // Wrap razorpay.open() in try-catch to catch any immediate errors
      try {
        razorpay.open();
        modalOpened = true;

        // Verify modal is visible after a short delay
        setTimeout(() => {
          const razorpayModal = document.querySelector('.razorpay-container, iframe[src*="razorpay.com"]');
          if (razorpayModal) {

            const computedStyle = window.getComputedStyle(razorpayModal);

          } else {

          }
        }, 500);
        
        // Note: The promise will resolve/reject via the onSuccess/onFailure callbacks
        // We don't resolve here - we wait for the payment callback
      } catch (openError) {

        reject(new Error(`Failed to open Razorpay modal: ${openError.message || openError}`));
      }
    } catch (error) {

      reject(error);
    }
  });
};

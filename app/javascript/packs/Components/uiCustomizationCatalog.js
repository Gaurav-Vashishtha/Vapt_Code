// Catalog for the "Checkout UI customization" editor (Pre-order OTP settings).
//
// Keys and English defaults MUST stay in sync with
// notifik-svelte-app/src/utils/uiCustomization.js — the widget resolves
// ui_customization.texts[key] → legacy setting → the same default shown here as
// the field placeholder.
//
// Api.js runs humps camelizeKeys on responses / decamelizeKeys on requests, so
// the nested jsonb keys come back camelCased. Everything in this module speaks
// the canonical snake_case; normalizeUiCustomization() maps a payload back.

import { camelize } from "humps";

export const UI_TEXT_GROUPS = [
  {
    title: "Cart items",
    section: "order_summary",
    preview: "order-summary",
    help: "The heading over the cart, and how each line reads.",
    items: [
      {
        key: "order_summary_title",
        label: "Heading",
        default: "Order summary",
      },
      {
        key: "saved_so_far",
        label: "Savings message",
        default: "Yay! You've saved {{amount}} so far",
        help: "Sits above the items. {{amount}} fills in with the total saved.",
      },
      {
        key: "item_singular",
        label: "Word for one item",
        default: "item",
        help: "Reads as \"1 item\".",
      },
      {
        key: "item_plural",
        label: "Word for several items",
        default: "items",
        help: "Reads as \"3 items\".",
      },
      {
        key: "qty",
        label: "Quantity",
        default: "Qty {{count}}",
        help: "{{count}} fills in with how many.",
      },
      {
        key: "remove_item_confirm",
        label: "Remove last item message",
        default: "Removing {{name}} will exit checkout.",
        help: "Shown when the last item is removed. {{name}} fills in with the product.",
      },
      {
        key: "remove_item_exit",
        label: "Remove and exit button",
        default: "Remove item & exit",
      },
      {
        key: "continue_checkout",
        label: "Continue checkout button",
        default: "Continue checkout",
      },
    ],
  },
  {
    title: "Items you may like",
    section: "order_summary",
    preview: "order-summary",
    help: "The upsell slider under the cart. Shown when Upsell is turned on.",
    items: [
      {
        key: "upsell_title",
        label: "Heading",
        default: "Items you may like",
      },
      {
        key: "upsell_add",
        label: "Add button",
        default: "Add",
      },
      {
        key: "upsell_added_toast",
        label: "Added message",
        default: "Product added to cart successfully",
        help: "Shown as a toast after a product is added.",
      },
      {
        key: "upsell_options",
        label: "Options button",
        default: "+{{count}} options",
        help: "Shown on products with variants. {{count}} fills in with how many.",
      },
      {
        key: "upsell_select_option",
        label: "Option label",
        default: "Select {{name}} :",
        help: "{{name}} fills in with the option, like Color.",
      },
      {
        key: "upsell_add_to_cart",
        label: "Add to cart button",
        default: "Add to cart",
      },
      {
        key: "upsell_adding",
        label: "Adding button",
        default: "Adding...",
        help: "Shown on the add to cart button while the item is being added.",
      },
    ],
  },
  {
    title: "Price breakdown",
    section: "order_summary",
    preview: "order-summary",
    help: "The rows between the cart and the total.",
    items: [
      {
        key: "billing_summary_title",
        label: "Heading",
        default: "Bill summary",
      },
      {
        key: "subtotal",
        label: "Subtotal row",
        default: "Subtotal",
      },
      {
        key: "discount",
        label: "Discount row",
        default: "Discount",
      },
      {
        key: "discount_with_name",
        label: "Discount row with a code",
        default: "Discount ({{name}})",
        help: "{{name}} fills in with the code.",
      },
      {
        key: "discount_on_mrp",
        label: "Discount off list price row",
        default: "Discount on MRP",
      },
    ],
  },
  {
    title: "Shipping and tax",
    section: "order_summary",
    preview: "order-summary",
    help: "Rows that depend on where the order is going.",
    items: [
      {
        key: "shipping",
        label: "Shipping row",
        default: "Shipping charges",
      },
      {
        key: "shipping_value",
        label: "Shipping amount before it is known",
        default: "Calculated at next step",
        help: "Sits where the figure goes until Shopify works the rate out.",
      },
      {
        key: "tax",
        label: "Tax row",
        default: "Tax",
      },
      {
        key: "tax_included_note",
        label: "Note when tax is in the price",
        default: "Price inclusive of all taxes",
      },
      {
        key: "tax_excluded_note",
        label: "Note when tax is added at checkout",
        default: "Taxes calculated at the next step",
      },
    ],
  },
  {
    title: "Total and empty cart",
    section: "order_summary",
    preview: "order-summary",
    help: "The last row, and what shows when there is nothing to buy.",
    items: [
      {
        key: "total_amount",
        label: "Total row",
        default: "Total amount",
      },
      {
        key: "no_items_in_cart",
        label: "Empty cart message",
        default: "No items in cart",
      },
    ],
  },
  {
    title: "Delivery address",
    section: "address",
    preview: "payment",
    help: "The chosen address, shown alongside the order.",
    items: [
      {
        key: "delivery_card_title",
        label: "Heading",
        default: "Delivery details",
      },
      {
        key: "delivery_no_address",
        label: "No address chosen",
        default: "No address selected",
      },
      {
        key: "delivery_add",
        label: "Add link",
        default: "Add",
      },
      {
        key: "delivery_change",
        label: "Change link",
        default: "Change",
      },
      {
        key: "delivery_edit_hint",
        label: "Edit address hint",
        default: "Click To Edit Address",
        help: "Tooltip shown briefly above the Change link on the delivery card.",
      },
    ],
  },
  {
    title: "Delivery summary",
    section: "address",
    preview: "payment",
    help: "Headings on the summary shown before paying.",
    items: [
      {
        key: "delivery_summary_title",
        label: "Address heading",
        default: "Delivery Details",
      },
      {
        key: "shipping_method_title",
        label: "Delivery speed heading",
        default: "Shipping Method",
      },
    ],
  },
  {
    title: "Payment list",
    section: "payments",
    preview: "payment",
    help: "The heading over the ways to pay, and what shows when there are none.",
    items: [
      {
        key: "payment_options_title",
        label: "Heading",
        default: "Pay via",
      },
      {
        key: "payment_options_perk",
        label: "Line under the heading",
        default: "Enjoy fast delivery on all prepaid orders",
      },
      {
        key: "no_payment_options",
        label: "No options available",
        default: "No payment options available at the moment",
      },
      {
        key: "no_rule_qualified",
        label: "No option fits this cart",
        default: "No payment option applies to your cart. You can close this window and try again.",
        help: "Shown when the cart matches none of your payment rules.",
      },
    ],
  },
  {
    title: "Fee badges",
    section: "payments",
    preview: "payment",
    help: "Extra charges called out on a payment option.",
    items: [
      {
        key: "cod_fee_badge",
        label: "Cash on delivery fee",
        default: "+{{amount}} COD fee",
        help: "{{amount}} fills in with the fee.",
      },
      {
        key: "free_delivery_badge",
        label: "Free delivery",
        default: "Free Delivery",
        help: "Shown on payment options whose rule offers free delivery.",
      },
      {
        key: "repeat_customer_badge",
        label: "Returning customer offer",
        default: "Returning customer offer",
        help: "Shown when a returning customer gets the extra discount.",
      },
      {
        key: "shipping_fee_badge",
        label: "Shipping charge",
        default: "+{{amount}} Shipping",
        help: "{{amount}} fills in with the charge.",
      },
      {
        key: "tax_hint",
        label: "Tax",
        default: "+ tax {{amount}}",
        help: "{{amount}} fills in with the tax.",
      },
    ],
  },
  {
    title: "Discount badges",
    section: "payments",
    preview: "payment",
    help: "Savings called out on a payment option.",
    items: [
      {
        key: "discount_badge_percent",
        label: "Badge for a percentage off",
        default: "🎉 Flat {{percent}}% Off",
        help: "{{percent}} fills in with the percentage.",
      },
      {
        key: "discount_badge_amount",
        label: "Badge for an amount off",
        default: "🎉 Flat {{amount}} Off",
        help: "{{amount}} fills in with the amount.",
      },
      {
        key: "option_save_percent",
        label: "Savings line, percentage offer",
        default: "Save {{percent}}%",
        help: "{{percent}} is the percentage, {{amount}} the same saving in money.",
      },
      {
        key: "option_save",
        label: "Savings line, amount offer",
        default: "Save {{amount}}",
        help: "{{amount}} is the amount saved, {{percent}} the same saving as a percentage.",
      },
    ],
  },
  {
    title: "Cash on delivery descriptions",
    section: "payments",
    preview: "payment",
    help: "The line under an option that is paid at the door. Placeholders: {{pay_now}}, {{pay_later}}, {{total}}, {{cod_fee}}. A description set on an individual rule still wins over these.",
    items: [
      {
        key: "desc_cod",
        label: "Pay in full on delivery",
        default: "Pay {{total}} on delivery",
      },
      {
        key: "desc_cod_with_fee",
        label: "Pay on delivery, with a fee",
        default: "Pay {{total}} on delivery ({{cod_fee}} COD fee applicable)",
      },
      {
        key: "desc_cod_fee_exception",
        label: "Pay only the fee now",
        default: "Pay {{pay_now}} cod fee now, remaining {{pay_later}} on delivery",
      },
      {
        key: "tap_to_read",
        label: "Expand a long description",
        default: "Tap to read",
        help: "Shown when a payment description is too long to fit.",
      },
    ],
  },
  {
    title: "Paying online descriptions",
    section: "payments",
    preview: "payment",
    help: "The line under an option that is paid up front. Placeholders: {{pay_now}}, {{pay_later}}, {{total}}, {{discount}}.",
    items: [
      {
        key: "desc_prepaid",
        label: "Pay in full now",
        default: "Pay {{pay_now}} now (prepaid)",
      },
      {
        key: "desc_prepaid_with_discount",
        label: "Pay now with a discount",
        default: "Pay {{pay_now}} now and get {{discount}} off",
      },
      {
        key: "desc_partial",
        label: "Pay part now",
        default: "Pay {{pay_now}} now and {{pay_later}} on delivery",
      },
      {
        key: "desc_pay_now_only",
        label: "Pay now, nothing later",
        default: "Pay {{pay_now}} now",
      },
    ],
  },
  {
    title: "Main button",
    section: "payments",
    preview: "payment",
    help: "The button at the bottom. Its wording changes with the step.",
    items: [
      {
        key: "cta_proceed",
        label: "Go to payment",
        default: "Proceed to Payment",
        help: "Replaces the older proceed button setting.",
      },
      {
        key: "cta_complete_order",
        label: "Place a cash on delivery order",
        default: "Complete Order",
      },
      {
        key: "cta_pay_now",
        label: "Open the payment window",
        default: "Pay Now",
      },
      {
        key: "cta_close",
        label: "Close",
        default: "Close",
      },
      {
        key: "cta_preparing",
        label: "While the cart loads",
        default: "Getting your order ready",
      },
    ],
  },
  {
    title: "Confirming the order",
    section: "payments",
    preview: "payment",
    help: "The last window before the order is placed.",
    items: [
      {
        key: "confirm_sheet_title",
        label: "Heading",
        default: "Confirm Your Order",
      },
      {
        key: "total_amount_inline",
        label: "Total label",
        default: "Total amount:",
      },
      {
        key: "cta_confirm_order",
        label: "Confirm button",
        default: "Confirm & place order",
      },
    ],
  },
  {
    title: "Payment window",
    section: "payments",
    preview: "payment",
    help: "The gateway window that opens after confirming.",
    items: [
      {
        key: "rzp_sheet_title",
        label: "Heading",
        default: "Complete Payment",
      },
      {
        key: "rzp_window_open",
        label: "Window is open",
        default: "Payment window is open",
      },
      {
        key: "rzp_window_note",
        label: "What to do in the window",
        default: "Complete the payment in the Razorpay window above, or close it to cancel.",
      },
      {
        key: "rzp_retry",
        label: "Retry button",
        default: "Retry",
      },
    ],
  },
  {
    title: "While payment loads",
    section: "payments",
    preview: "payment",
    help: "Shown for a moment while the gateway is being set up.",
    items: [
      {
        key: "rzp_initializing",
        label: "Setting up",
        default: "Initializing payment...",
      },
      {
        key: "rzp_loading",
        label: "Loading the gateway",
        default: "Loading payment gateway...",
      },
    ],
  },
  {
    title: "Footer and policy links",
    section: "branding",
    preview: "phone",
    help: "The small print along the bottom of the window.",
    items: [
      {
        key: "legal_prefix",
        label: "Words before the links",
        default: "",
        help: "Only shown while the COD King mark is visible. Leave blank to hide it.",
      },
      {
        key: "legal_terms",
        label: "Terms link, short",
        default: "T&C",
        help: "Used while the COD King mark is visible and space is tight.",
      },
      {
        key: "legal_terms_full",
        label: "Terms link, full",
        default: "Terms & Conditions",
        help: "Used instead of the short one when you hide COD King branding.",
      },
      {
        key: "legal_privacy",
        label: "Privacy link",
        default: "Privacy Policy",
      },
    ],
  },
  {
    title: "Phone number screen",
    section: "login",
    preview: "phone",
    help: "The first screen, where the shopper types their number.",
    items: [
      {
        key: "phone_title",
        label: "Heading",
        default: "Enter mobile number",
      },
      {
        key: "phone_subtitle",
        label: "Line under the heading",
        default: "Provide your mobile number to continue",
      },
      {
        key: "phone_continue_with",
        label: "Heading over a saved number",
        default: "Continue with",
      },
      {
        key: "phone_send_otp_via",
        label: "Label over SMS and WhatsApp",
        default: "Send OTP via",
      },
      {
        key: "close",
        label: "Close button",
        default: "Close",
      },
    ],
  },
  {
    title: "Verify code screen",
    section: "verification",
    preview: "otp",
    help: "Where the shopper types the code you sent them.",
    items: [
      {
        key: "otp_resend_via",
        label: "Label over the resend choices",
        default: "Resend OTP via",
      },
      {
        key: "otp_channel_sms",
        label: "Name for SMS",
        default: "SMS",
      },
      {
        key: "login_not_you",
        label: "Start over with another number",
        default: "Not you?",
      },
      {
        key: "go_to_phone_screen",
        label: "Back to the phone number screen",
        default: "Go to Phone Screen",
      },
    ],
  },
  {
    title: "Name and street",
    section: "address",
    preview: "address-form",
    help: "Who the order is for, and where it goes.",
    items: [
      {
        key: "addr_first_name",
        label: "First name",
        default: "First name",
      },
      {
        key: "addr_last_name",
        label: "Last name",
        default: "Last name",
      },
      {
        key: "addr_line1",
        label: "Address line 1",
        default: "Flat, house number, floor, building",
        help: "The house, flat or building.",
      },
      {
        key: "addr_line2",
        label: "Address line 2",
        default: "Area, street, sector, village",
        help: "The street, area or village.",
      },
      {
        key: "addr_landmark",
        label: "Landmark",
        default: "Landmark",
      },
    ],
  },
  {
    title: "Postcode, city and state",
    section: "address",
    preview: "address-form",
    help: "The part of the address that decides whether you can deliver.",
    items: [
      {
        key: "addr_pincode",
        label: "Postcode",
        default: "Pincode",
        help: "Shows as Pincode for Indian shoppers and Postal code elsewhere.",
      },
      {
        key: "addr_validating_pincode",
        label: "Looking up the postcode",
        default: "Validating pincode...",
      },
      {
        key: "addr_city",
        label: "City",
        default: "City",
      },
      {
        key: "addr_state",
        label: "State",
        default: "State",
      },
      {
        key: "addr_postal_code",
        label: "Postal code",
        default: "Postal code",
        help: "Used instead of Pincode outside India.",
      },
    ],
  },
  {
    title: "Email",
    section: "address",
    preview: "address-form",
    help: "Where the order confirmation is sent.",
    items: [
      {
        key: "addr_email",
        label: "Email",
        default: "E-mail",
      },
      {
        key: "addr_email_note",
        label: "Note under the field",
        default: "Order delivery details will be sent here",
      },
    ],
  },
  {
    title: "Address type",
    section: "address",
    preview: "address-form",
    help: "Home, work or somewhere else, so a courier knows what to expect.",
    items: [
      {
        key: "addr_type_title",
        label: "Heading",
        default: "Address type",
      },
      {
        key: "addr_type_home",
        label: "Home option",
        default: "Home",
      },
      {
        key: "addr_type_office",
        label: "Work option",
        default: "Office",
      },
      {
        key: "addr_type_other",
        label: "Other option",
        default: "Others",
      },
    ],
  },
  {
    title: "Saved address list",
    section: "address",
    preview: "address",
    help: "The list a returning shopper picks from.",
    items: [
      {
        key: "saved_addresses_title",
        label: "Heading",
        default: "Saved addresses",
      },
      {
        key: "addr_intro",
        label: "Line under the heading",
        default: "Including addresses linked to {{phone}} where we can deliver your order.",
        help: "{{phone}} fills in with their verified number. Shown when COD King collects the address.",
      },
      {
        key: "addr_intro_checkout",
        label: "Line under the heading, prefill only",
        default: "Including addresses linked to {{phone}}. Pick one and we'll fill it in at checkout.",
        help: "Shown instead when the address is only carried into Shopify checkout.",
      },
      {
        key: "addr_edit",
        label: "Edit link",
        default: "Edit",
      },
    ],
  },
  {
    title: "Adding an address",
    section: "address",
    preview: "address",
    help: "What a shopper sees when they have none saved, or want another.",
    items: [
      {
        key: "addr_add_new",
        label: "Add another button",
        default: "Add new address",
      },
      {
        key: "addr_add_first",
        label: "Add the first button",
        default: "Add your first address",
      },
      {
        key: "addr_none_saved",
        label: "Nothing saved yet",
        default: "No saved addresses yet. Add one to continue.",
      },
    ],
  },
  {
    title: "Coupon window",
    section: "coupons",
    preview: "coupons",
    help: "Where a shopper types or picks a code.",
    items: [
      {
        key: "coupon_sheet_title",
        label: "Heading",
        default: "Apply Coupon",
      },
      {
        key: "coupon_placeholder",
        label: "Grey text in the code box",
        default: "Enter coupon code",
      },
      {
        key: "coupon_apply",
        label: "Apply link",
        default: "Apply",
      },
      {
        key: "coupon_have_code",
        label: "Have a coupon prompt",
        default: "Already have a coupon ?",
      },
    ],
  },
  {
    title: "Coupon lists",
    section: "coupons",
    preview: "coupons",
    help: "How the coupons are grouped inside that window.",
    items: [
      {
        key: "coupon_applicable",
        label: "Heading for coupons they can use",
        default: "Applicable coupons",
      },
      {
        key: "coupon_unlock",
        label: "Heading for coupons they cannot use yet",
        default: "Unlock Coupons",
        help: "These need a bigger cart, or another condition met first.",
      },
      {
        key: "coupon_none",
        label: "No coupons message",
        default: "No offers available right now.",
      },
    ],
  },
  {
    title: "Applied coupon",
    section: "coupons",
    preview: "coupons",
    help: "Once a code is on the order.",
    items: [
      {
        key: "coupon_saved",
        label: "Applied label",
        default: "Saved",
      },
      {
        key: "coupon_tap_remove",
        label: "Remove hint",
        default: "Tap to remove",
      },
    ],
  },
  {
    title: "Leaving checkout",
    section: "messages",
    preview: "dialogs",
    help: "The warning shown when a shopper closes the window part way through.",
    items: [
      {
        key: "exit_confirm_title",
        label: "Question asked",
        default: "Are you sure you want to exit?",
      },
      {
        key: "close_confirm_banner",
        label: "Warning",
        default: "Products in huge demand might run Out of Stock",
      },
      {
        key: "close_confirm_banner_saved",
        label: "Warning when a discount is at stake",
        default: "You might miss out on savings of {{amount}}",
        help: "{{amount}} fills in with what they would lose.",
      },
      {
        key: "close_confirm_continue",
        label: "Stay button",
        default: "No, continue checkout",
      },
      {
        key: "close_confirm_leave",
        label: "Leave button",
        default: "Yes, exit checkout",
      },
    ],
  },
  {
    title: "Logging out",
    section: "messages",
    preview: "dialogs",
    help: "Shown when a signed-in shopper chooses to log out.",
    items: [
      {
        key: "logout_confirm_title",
        label: "Question asked",
        default: "Are you sure you want to log out?",
      },
      {
        key: "logout_confirm_message",
        label: "Line under the question",
        default: "You'll need to verify with OTP again next time",
      },
      {
        key: "logout_stay",
        label: "Cancel button",
        default: "No, stay logged in",
      },
    ],
  },
  {
    title: "Order placed and errors",
    section: "messages",
    preview: "dialogs",
    help: "The short messages that appear over the top.",
    items: [
      {
        key: "celebration_thanks",
        label: "After the order goes through",
        default: "Woohoo! Thanks",
      },
      {
        key: "try_again",
        label: "Retry button on an error",
        default: "Try Again",
      },
    ],
  },
  {
    title: "Loading and redirect screens",
    section: "messages",
    preview: "dialogs",
    help: "What the shopper reads while the cart opens or the page moves on.",
    items: [
      { key: "cart_loader_title", label: "Opening checkout, heading", default: "Loading your checkout…" },
      { key: "cart_loader_subtitle", label: "Opening checkout, line under it", default: "Fetching cart details securely" },
      { key: "cart_loader_progress", label: "Opening checkout, progress", default: "Getting your cart details..." },
      { key: "cart_loader_proceeding", label: "After a payment method is picked", default: "Getting your cart details..." },
      { key: "cart_loader_error", label: "Cart could not load", default: "We couldn't load your cart. Please refresh the page and try again." },
      { key: "cart_loader_fallback", label: "Placeholder when there is no logo", default: "Loading…" },
      { key: "loader_title", label: "Payment screen loader, heading", default: "Preparing your secure checkout" },
      { key: "loader_subtitle", label: "Payment screen loader, line under it", default: "Fetching cart details securely" },
      { key: "redirect_title", label: "Redirecting, heading", default: "Redirecting to checkout…" },
      { key: "redirect_subtitle", label: "Redirecting, line under it", default: "OTP Verified! You're all set. Redirecting to checkout." },
      { key: "order_processing", label: "Placing a COD order", default: "Processing your order…" },
      { key: "order_confirmed_redirect", label: "COD order confirmed", default: "Order is confirmed, redirecting you to orders page…" },
    ],
  },
  {
    title: "Order confirmation screen",
    section: "messages",
    preview: "dialogs",
    help: "The screen a shopper lands on once the order is placed.",
    items: [
      { key: "oc_thank_you", label: "Heading", default: "Thank you for your order!" },
      { key: "oc_placed", label: "Order placed", default: "Your order has been successfully placed." },
      { key: "oc_preparing", label: "Preparing note", default: "We're preparing your order and will notify you once it ships." },
      { key: "oc_order_number", label: "Order number", default: "Order Number" },
      { key: "oc_payment_method", label: "Payment method", default: "Payment Method" },
      { key: "oc_estimated_delivery", label: "Estimated delivery", default: "Estimated Delivery" },
      { key: "oc_updates_note", label: "Updates note", default: "You will receive updates about your order via SMS or WhatsApp." },
      { key: "oc_track_order", label: "Track order button", default: "Track Order" },
      { key: "oc_view_orders", label: "View orders button", default: "View orders" },
      { key: "oc_continue_shopping", label: "Continue shopping button", default: "Continue Shopping" },
    ],
  },
];

export const UI_TEXT_ITEMS = UI_TEXT_GROUPS.flatMap((group) => group.items);

export const UI_TEXT_KEYS = UI_TEXT_ITEMS.map((item) => item.key);

export const UI_TEXT_DEFAULTS = UI_TEXT_ITEMS.reduce((acc, item) => {
  acc[item.key] = item.default;
  return acc;
}, {});

export const UI_BRANDING_KEYS = ["hide_footer_branding", "terms_url", "privacy_url", "whatsapp_primary", "brand_color"];

export const UI_DEFAULT_BRAND_COLOR = "#3173e3";

// ---------------------------------------------------------------------------
// Widget visibility — which storefront pages the app-embed script boots on.
// Values mirror Liquid's request.page_type; keep in sync with
// Setting::UI_CUSTOMIZATION_PAGE_TYPES and the app-embed.liquid gate.
// ---------------------------------------------------------------------------

export const UI_VISIBILITY_MODES = ["all", "exclude", "include"];

export const UI_VISIBILITY_PAGE_TYPES = [
  { value: "index", label: "Home page" },
  { value: "product", label: "Product pages" },
  { value: "collection", label: "Collection pages" },
  { value: "list-collections", label: "All collections page" },
  { value: "cart", label: "Cart page" },
  { value: "search", label: "Search results" },
  { value: "page", label: "Static pages (About, FAQ…)" },
  { value: "blog", label: "Blog listing" },
  { value: "article", label: "Blog posts" },
  { value: "policy", label: "Policy pages" },
  { value: "customers/account", label: "Customer account" },
  { value: "customers/login", label: "Customer login" },
  { value: "customers/register", label: "Customer register" },
  { value: "customers/order", label: "Customer order status" },
  { value: "customers/addresses", label: "Customer addresses" },
  { value: "password", label: "Password page" },
  { value: "gift_card", label: "Gift card page" },
  { value: "404", label: "404 page" },
];

const UI_VISIBILITY_PAGE_TYPE_VALUES = UI_VISIBILITY_PAGE_TYPES.map((t) => t.value);

export const MAX_VISIBILITY_PATHS = 50;

/** `/pages/About/` and `pages/about` both mean the same rule. */
export const normalizeVisibilityPath = (value) => {
  let path = String(value ?? "").trim().toLowerCase().split("?")[0].split("#")[0];
  if (!path) return "";
  if (path.length > 200) return "";
  if (!path.startsWith("/")) path = `/${path}`;
  if (path.length > 1 && path.endsWith("/")) path = path.slice(0, -1);
  return path;
};

export const normalizeWidgetVisibility = (raw) => {
  const source = raw || {};
  const mode = String(source.mode ?? "").trim().toLowerCase();
  const pageTypes = source.page_types ?? source.pageTypes;

  return {
    mode: UI_VISIBILITY_MODES.includes(mode) ? mode : "all",
    page_types: (Array.isArray(pageTypes) ? pageTypes : [])
      .map((type) => String(type ?? "").trim().toLowerCase())
      .filter((type, index, all) =>
        UI_VISIBILITY_PAGE_TYPE_VALUES.includes(type) && all.indexOf(type) === index
      ),
    paths: (Array.isArray(source.paths) ? source.paths : [])
      .map(normalizeVisibilityPath)
      .filter((path, index, all) => path && all.indexOf(path) === index)
      .slice(0, MAX_VISIBILITY_PATHS),
  };
};

const snakeKeyByCamel = (keys) =>
  keys.reduce((acc, key) => {
    acc[camelize(key)] = key;
    return acc;
  }, {});

const TEXT_KEY_BY_CAMEL = snakeKeyByCamel(UI_TEXT_KEYS);
const BRANDING_KEY_BY_CAMEL = snakeKeyByCamel(UI_BRANDING_KEYS);

const toCanonical = (source, keyByCamel, validKeys) => {
  const out = {};
  Object.entries(source || {}).forEach(([key, value]) => {
    const canonical = validKeys.includes(key) ? key : keyByCamel[key];
    if (canonical !== undefined) out[canonical] = value;
  });
  return out;
};

/**
 * Accepts whatever `setting.uiCustomization` currently holds (camelCase from the
 * API, snake_case from local edits) and returns the canonical shape.
 */
export const normalizeUiCustomization = (raw) => ({
  texts: toCanonical(raw?.texts, TEXT_KEY_BY_CAMEL, UI_TEXT_KEYS),
  branding: toCanonical(raw?.branding, BRANDING_KEY_BY_CAMEL, UI_BRANDING_KEYS),
  widget_visibility: normalizeWidgetVisibility(
    raw?.widget_visibility ?? raw?.widgetVisibility
  ),
});

/** Every key with its current value, defaults filled in — for bulk translation. */
export const buildBulkTexts = (texts) =>
  UI_TEXT_KEYS.reduce((acc, key) => {
    acc[key] = (texts?.[key] ?? "").toString().trim() || UI_TEXT_DEFAULTS[key];
    return acc;
  }, {});

/**
 * Parse a pasted bulk-translation object. Known keys only; a value left at the
 * English default (or blanked) is reported as a reset instead of an override, so
 * pasting the untouched export stores nothing.
 *
 * @returns {{texts: Record<string,string>, resetKeys: string[], unknownKeys: string[], count: number}}
 */
export const parseBulkTexts = (parsed) => {
  const texts = {};
  const resetKeys = [];
  const unknownKeys = [];

  Object.entries(parsed || {}).forEach(([rawKey, rawValue]) => {
    const key = UI_TEXT_KEYS.includes(rawKey) ? rawKey : TEXT_KEY_BY_CAMEL[rawKey];
    if (!key) {
      unknownKeys.push(rawKey);
      return;
    }
    if (typeof rawValue !== "string") return;

    const value = rawValue.trim();
    if (!value || value === UI_TEXT_DEFAULTS[key]) {
      resetKeys.push(key);
      return;
    }

    texts[key] = value;
  });

  return { texts, resetKeys, unknownKeys, count: Object.keys(texts).length };
};

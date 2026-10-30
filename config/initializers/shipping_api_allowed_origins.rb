# frozen_string_literal: true

# Public shipping helpers (shipping_address_count, shipping_addresses) optionally
# require a matching Origin / Referer when ENV["SHIPPING_API_ALLOWED_ORIGINS"] is set.
#
# Comma-separated rules, e.g.:
#   SHIPPING_API_ALLOWED_ORIGINS=https://checkout.shopify.com,*.myshopify.com,https://cdn.shopify.com
#
# When unset or empty, origin checks are skipped (existing storefront clients keep working).
#
# Server-to-server (no browser Origin): set the same secret on both sides:
#   SHIPPING_API_SERVER_SECRET=<long-random-string>
# Caller must send either header:
#   X-Shipping-Api-Secret: <same value>
# or:
#   Authorization: Bearer <same value>
# If the secret matches, the request is allowed even when origin rules are configured.
#
# To require the secret for ALL requests (recommended when calling from another server),
# set:
#   SHIPPING_API_REQUIRE_SECRET=true
#
# See: ShippingApi::OriginValidator

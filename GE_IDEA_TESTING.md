# GE_IDEA Integration Testing Guide

## Database Queries to Update Settings

### 1. Update a Shop's Payment Provider to GE_IDEA

```sql
-- Replace YOUR_SHOP_ID with the actual shop ID
UPDATE settings 
SET 
  payment_provider = 'GE_IDEA',
  payment_provider_api_key = 'YOUR_MERCHANT_PUBLIC_KEY',
  payment_provider_api_secret = 'YOUR_MERCHANT_SECRET_KEY',
  prepaid_enabled = true
WHERE shop_id = YOUR_SHOP_ID;
```

### 2. Set Test Credentials (Use from your curl example)

```sql
UPDATE settings 
SET 
  payment_provider = 'GE_IDEA',
  payment_provider_api_key = 'c0eb05e9-1e27-4736-a795-3060c4f8117c',
  payment_provider_api_secret = 'd82e977a-9705-4524-b8ad-841979e4f668',
  prepaid_enabled = true
WHERE shop_id = YOUR_SHOP_ID;
```

### 3. Find Order Confirmations for Testing

```sql
-- Find COD orders that can be tested
SELECT 
  oc.id,
  oc.order_id,
  oc.customer_name,
  oc.customer_number,
  oc.customer_email,
  oc.order_amount,
  oc.currency,
  oc.country_code,
  oc.status,
  s.shopify_domain,
  s.setting.payment_provider
FROM order_confirmations oc
JOIN shops s ON oc.shop_id = s.id
JOIN settings st ON st.shop_id = s.id
WHERE 
  oc.is_cod_order = true
  AND oc.status != 'COD-Prepaid'
  AND st.payment_provider = 'GE_IDEA'
  AND st.prepaid_enabled = true
LIMIT 10;
```

## Rails Console Testing Commands

### 1. Test Payment Link Creation

```ruby
# Find a shop with GE_IDEA configured
shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first

# Find an order confirmation for testing
order_confirmation = shop.order_confirmations.where(is_cod_order: true).where.not(status: 'COD-Prepaid').first

# If order_confirmation doesn't exist, create a test one
if order_confirmation.nil?
  order_confirmation = OrderConfirmation.create!(
    shop: shop,
    order_id: "TEST_#{Time.now.to_i}",
    order_amount: 100.0,
    currency: "EGP",
    customer_name: "Test Customer",
    customer_number: "1234567890",
    customer_email: "test@example.com",
    country_code: "EG",
    status: "Pending",
    is_cod_order: true
  )
end

# Test creating payment link
link = NetworkServices::GeideaLinkService.call(shop, order_confirmation)
puts "Payment Link: #{link}"

# Check order_confirmation updates
puts "Prepaid Link: #{order_confirmation.prepaid_link}"
puts "Payment Intent ID: #{order_confirmation.phonepe_transaction_ids}"
puts "Prepaid Status: #{order_confirmation.prepaid_status}"
puts "Digest: #{order_confirmation.digest}"
```

### 2. Test Payment Status Check

```ruby
# Use an order_confirmation that has a payment_intent_id stored
shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first
order_confirmation = shop.order_confirmations.where.not(phonepe_transaction_ids: nil).first

# If you need to manually set a payment_intent_id for testing
# order_confirmation.update(phonepe_transaction_ids: "YOUR_PAYMENT_INTENT_ID")

# Test status check
status = NetworkServices::GeideaStatusService.call(shop, order_confirmation)
puts "Payment Status (Paid): #{status}"
```

### 3. Test Complete Flow

```ruby
# Setup
shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first

# Create or find order confirmation
order_confirmation = shop.order_confirmations.where(is_cod_order: true).first || 
  OrderConfirmation.create!(
    shop: shop,
    order_id: "FLOW_TEST_#{Time.now.to_i}",
    order_amount: 150.0,
    currency: "EGP",
    customer_name: "Flow Test Customer",
    customer_number: "9876543210",
    customer_email: "flowtest@example.com",
    country_code: "EG",
    status: "Pending",
    is_cod_order: true
  )

# Step 1: Create payment link
puts "Step 1: Creating payment link..."
link = NetworkServices::GeideaLinkService.call(shop, order_confirmation)
puts "Link created: #{link}"

# Step 2: Wait a moment (if payment was made)
sleep 5

# Step 3: Check payment status
puts "Step 2: Checking payment status..."
status = NetworkServices::GeideaStatusService.call(shop, order_confirmation)
puts "Status (Paid?): #{status}"

# Step 4: If paid, convert to prepaid
if status
  puts "Step 3: Converting to prepaid..."
  result = ShopifyServices::PrepaidOrderService.call(shop, order_confirmation.id)
  puts "Conversion result: #{result}"
end
```

### 4. Test Controller Actions

```ruby
# Test redirect_to_prepaid_link
order_confirmation = OrderConfirmation.where.not(digest: nil).first
digest = order_confirmation.digest

# In Rails console, you can simulate controller call:
# This would be called via HTTP GET to: /order/prepaid?digest=#{digest}
# The controller will call: NetworkServices::GeideaLinkService.call(...)
```

### 5. Test Workers

```ruby
# Test PrepaidConversionJob
order_confirmation = OrderConfirmation.where(prepaid_status: 'CALLBACK-RECEIVED').first

# Manually trigger the job logic
if order_confirmation.shop.setting.payment_provider == 'GE_IDEA'
  if NetworkServices::GeideaStatusService.call(order_confirmation.shop, order_confirmation)
    prepaid_resp = ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
    puts "Converted to prepaid: #{prepaid_resp.present?}"
  end
end

# Or trigger the actual job
ShopifyJobs::PrepaidConversionJob.new.perform
```

### 6. Test Send Prepaid Message Service

```ruby
shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first
order_confirmation = shop.order_confirmations.where(is_cod_order: true).first

# This will create the payment link if it doesn't exist
result = NetworkServices::SendPrepaidMessageService.call(shop, order_confirmation)
puts "Message service result: #{result}"
puts "Order confirmation prepaid_link: #{order_confirmation.reload.prepaid_link}"
```

### 7. Debug Service Calls

```ruby
# Enable detailed logging
require 'net/http'
require 'uri'
require 'json'
require 'base64'

shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first
order_confirmation = shop.order_confirmations.where(is_cod_order: true).first

# Create auth header
credentials = "#{shop.setting.payment_provider_api_key}:#{shop.setting.payment_provider_api_secret}"
auth_header = "Basic #{Base64.strict_encode64(credentials)}"
puts "Auth Header: #{auth_header}"

# Check service initialization
service = NetworkServices::GeideaLinkService.new(shop, order_confirmation)
puts "Service initialized: #{service.present?}"
```

## Verification Checklist

- [ ] Payment provider set to 'GE_IDEA' in settings
- [ ] API Key and Secret configured correctly
- [ ] Prepaid enabled is true
- [ ] Order confirmation has customer details (name, email, phone, country_code)
- [ ] Payment link is created successfully
- [ ] Payment Intent ID is stored in order_confirmation.phonepe_transaction_ids
- [ ] Prepaid status is set to 'CALLBACK-RECEIVED'
- [ ] Status check returns correct boolean
- [ ] Workers process GE_IDEA orders correctly
- [ ] Frontend shows GE_IDEA option in payment provider dropdown

## Common Issues and Fixes

### Issue: "Authentication failed"
- **Fix**: Verify API key and secret are correct. Check Base64 encoding.

### Issue: "Payment Intent ID not found"
- **Fix**: Ensure payment link was created successfully and paymentIntentId was stored.

### Issue: "Phone number format error"
- **Fix**: Verify customer_number and country_code are set correctly in order_confirmation.

### Issue: "Currency not supported"
- **Fix**: Default currency is EGP. Ensure order_confirmation.currency is set or defaults to EGP.

### Issue: "Status check returns false for paid orders"
- **Fix**: Verify the paymentIntentId is correct and the order status in GE_IDEA dashboard is "Paid".


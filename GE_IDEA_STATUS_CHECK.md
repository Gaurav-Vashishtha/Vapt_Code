# GE_IDEA Payment Status Check - Rails Console Commands

## Quick Status Check

```ruby
# Find shop with GE_IDEA configured
shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first

# Find order confirmation that has a paymentIntentId (from link creation)
order_confirmation = shop.order_confirmations.where.not(phonepe_transaction_ids: nil).first

# Check payment status
status = NetworkServices::GeideaStatusService.call(shop, order_confirmation)
puts "Payment Status (Paid?): #{status}"
```

## Complete Status Check with Details

```ruby
# Setup
shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first

# Find order confirmation with payment intent ID
order_confirmation = shop.order_confirmations.where.not(phonepe_transaction_ids: nil).first

# Check if paymentIntentId exists
if order_confirmation.phonepe_transaction_ids.present?
  puts "Payment Intent ID: #{order_confirmation.phonepe_transaction_ids}"
  
  # Check status
  status = NetworkServices::GeideaStatusService.call(shop, order_confirmation)
  
  puts "\n=== Payment Status Check ==="
  puts "Order ID: #{order_confirmation.order_id}"
  puts "Payment Intent ID: #{order_confirmation.phonepe_transaction_ids}"
  puts "Status (Paid?): #{status}"
  puts "Prepaid Status: #{order_confirmation.prepaid_status}"
  
  if status
    puts "✅ Payment is PAID - Ready to convert to prepaid"
  else
    puts "❌ Payment is NOT PAID yet"
  end
else
  puts "No paymentIntentId found. Create payment link first."
end
```

## Manual Status Check with Specific Payment Intent ID

```ruby
# If you have a paymentIntentId from GE_IDEA dashboard or link response
shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first
order_confirmation = shop.order_confirmations.first

# Manually set paymentIntentId for testing
payment_intent_id = "YOUR_PAYMENT_INTENT_ID_HERE"
order_confirmation.update(phonepe_transaction_ids: payment_intent_id)

# Now check status
status = NetworkServices::GeideaStatusService.call(shop, order_confirmation)
puts "Status: #{status}"
```

## Check Status After Link Creation

```ruby
# Step 1: Create payment link
shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first
order_confirmation = shop.order_confirmations.where(is_cod_order: true).first

# Create link (this stores paymentIntentId)
link = NetworkServices::GeideaLinkService.call(shop, order_confirmation)
puts "Payment Link: #{link}"
puts "Payment Intent ID: #{order_confirmation.reload.phonepe_transaction_ids}"

# Step 2: Wait a few seconds (if payment was made manually)
sleep 5

# Step 3: Check status
status = NetworkServices::GeideaStatusService.call(shop, order_confirmation)
puts "Payment Status: #{status ? 'PAID' : 'NOT PAID'}"

# Step 4: If paid, convert to prepaid
if status
  result = ShopifyServices::PrepaidOrderService.call(shop, order_confirmation.id)
  puts "Conversion result: #{result}"
end
```

## Debug Status Check (Raw API Call)

```ruby
require 'net/http'
require 'uri'
require 'json'
require 'base64'

shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first
order_confirmation = shop.order_confirmations.where.not(phonepe_transaction_ids: nil).first

payment_intent_id = order_confirmation.phonepe_transaction_ids

# Create auth header
credentials = "#{shop.setting.payment_provider_api_key}:#{shop.setting.payment_provider_api_secret}"
auth_header = "Basic #{Base64.strict_encode64(credentials)}"

# Make request
uri = URI("https://api.merchant.geidea.net/pgw/api/v1/direct/order")
response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
  req = Net::HTTP::Get.new(uri.path)
  req["paymentIntentId"] = payment_intent_id
  req["Authorization"] = auth_header
  req["Accept"] = "application/json"
  http.request(req)
end

# Parse response
result = JSON.parse(response.body)

puts "=== Raw API Response ==="
puts "HTTP Status: #{response.code}"
puts "Response Code: #{result['responseCode']}"
puts "Detailed Status: #{result.dig('order', 'detailedStatus')}"
puts "Status: #{result.dig('order', 'status')}"
puts "Amount: #{result.dig('order', 'amount')}"
puts "Currency: #{result.dig('order', 'currency')}"
puts "\nFull Response:"
puts JSON.pretty_generate(result)
```

## Check All GE_IDEA Orders Status

```ruby
shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first

# Get all orders with payment intent IDs
order_confirmations = shop.order_confirmations
  .where.not(phonepe_transaction_ids: nil)
  .where(prepaid_status: 'CALLBACK-RECEIVED')
  .limit(10)

order_confirmations.each do |oc|
  status = NetworkServices::GeideaStatusService.call(shop, oc)
  puts "#{oc.order_id}: #{oc.phonepe_transaction_ids} -> #{status ? 'PAID' : 'NOT PAID'}"
end
```

## Test Complete Flow

```ruby
# Complete test: Create link, wait, check status, convert if paid
shop = Shop.joins(:setting).where(settings: { payment_provider: 'GE_IDEA' }).first
order_confirmation = shop.order_confirmations.where(is_cod_order: true).where(status: 'Pending').first

# Create payment link
puts "Step 1: Creating payment link..."
link = NetworkServices::GeideaLinkService.call(shop, order_confirmation)
puts "✅ Link created: #{link}"

# Reload to get paymentIntentId
order_confirmation.reload
puts "Payment Intent ID: #{order_confirmation.phonepe_transaction_ids}"

# Wait (simulate payment being made)
puts "\nStep 2: Waiting 10 seconds (simulate payment)..."
puts "NOTE: In production, payment would be made on GE_IDEA gateway"
sleep 10

# Check status
puts "\nStep 3: Checking payment status..."
status = NetworkServices::GeideaStatusService.call(shop, order_confirmation)
puts "Status: #{status ? '✅ PAID' : '❌ NOT PAID'}"

# Convert to prepaid if paid
if status
  puts "\nStep 4: Converting to prepaid..."
  result = ShopifyServices::PrepaidOrderService.call(shop, order_confirmation.id)
  puts "✅ Conversion result: #{result}"
else
  puts "\nStep 4: Payment not completed, skipping conversion"
end
```

## Troubleshooting

### If paymentIntentId is missing:
```ruby
# Check if link was created successfully
order_confirmation.reload
puts "Prepaid Link: #{order_confirmation.prepaid_link}"
puts "Payment Intent ID: #{order_confirmation.phonepe_transaction_ids}"
puts "Prepaid Status: #{order_confirmation.prepaid_status}"
```

### If status check returns false:
```ruby
# Check the raw API response for details
# Use the "Debug Status Check (Raw API Call)" code above
```

### If authentication fails:
```ruby
# Verify credentials
shop.setting.payment_provider_api_key
shop.setting.payment_provider_api_secret

# Test auth header
credentials = "#{shop.setting.payment_provider_api_key}:#{shop.setting.payment_provider_api_secret}"
auth_header = "Basic #{Base64.strict_encode64(credentials)}"
puts "Auth Header: #{auth_header}"
```


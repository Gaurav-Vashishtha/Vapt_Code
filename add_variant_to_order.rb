# Rails Console Method: Add Variant to Order
# Usage in rails c:
#   add_variant_to_order(shop, order_id, variant_id, quantity = 1)

def add_variant_to_order(shop, order_id, variant_id, quantity = 1)
  # Initialize shop session and get GraphQL client
  shop.init_session
  client = ShopifyAPI::GraphQL.client
  
  # STEP 1: Start order edit session
  puts "Starting order edit session for order #{order_id}..."
  begin_order_edit_query = client.parse <<-'GRAPHQL'
    mutation($id:ID!) {
      orderEditBegin(id:$id){
        calculatedOrder{
          id
        }
        userErrors {
          field
          message
        }
      }
    }
  GRAPHQL
  
  begin_variables = {
    id: "gid://shopify/Order/#{order_id}"
  }
  
  begin_response = client.query(begin_order_edit_query, variables: begin_variables)
  
  if begin_response&.data&.order_edit_begin&.user_errors&.any?
    errors = begin_response.data.order_edit_begin.user_errors
    error_messages = errors.map { |e| e.message }.join(", ")
    puts "❌ Error starting order edit: #{error_messages}"
    return { success: false, error: error_messages }
  end
  
  calculated_order_id = begin_response&.data&.order_edit_begin&.calculated_order&.id
  
  unless calculated_order_id.present?
    puts "❌ Could not get calculated order ID"
    return { success: false, error: "Could not get calculated order ID" }
  end
  
  puts "✅ Order edit session started. Calculated order ID: #{calculated_order_id}"
  
  # STEP 2: Add variant
  puts "Adding variant #{variant_id} with quantity #{quantity}..."
  add_variant_query = client.parse <<-'GRAPHQL'
    mutation ($id:ID!,$variantId:ID!, $quantity:Int!) {
      orderEditAddVariant(id: $id, variantId: $variantId , quantity: $quantity){
        calculatedOrder {
          id
          addedLineItems(first:5) {
            edges {
              node {
                id
                variant {
                  id
                  title
                }
                quantity
              }
            }
          }
        }
        userErrors {
          field
          message
        }
      }
    }
  GRAPHQL
  
  add_variables = {
    id: calculated_order_id,
    variantId: "gid://shopify/ProductVariant/#{variant_id}",
    quantity: quantity.to_i
  }
  
  add_response = client.query(add_variant_query, variables: add_variables)
  
  if add_response&.data&.order_edit_add_variant&.user_errors&.any?
    errors = add_response.data.order_edit_add_variant.user_errors
    error_messages = errors.map { |e| e.message }.join(", ")
    puts "❌ Error adding variant: #{error_messages}"
    return { success: false, error: error_messages }
  end
  
  added_line_items = add_response&.data&.order_edit_add_variant&.calculated_order&.added_line_items&.edges
  if added_line_items.present? && added_line_items.any?
    added_item = added_line_items.first.node
    puts "✅ Successfully added variant: #{added_item.variant.title} (ID: #{added_item.variant.id})"
    puts "   Line item ID: #{added_item.id}, Quantity: #{added_item.quantity}"
  else
    puts "⚠️ Variant added but could not retrieve line item details"
  end
  
  # STEP 3: Commit the order
  puts "Committing order changes..."
  commit_query = client.parse <<-'GRAPHQL'
    mutation ($id:ID!)  {
      orderEditCommit(id: $id, notifyCustomer: false, staffNote: "Added variant via console") {
        order {
          id
        }
        userErrors {
          field
          message
        }
      }
    }
  GRAPHQL
  
  commit_variables = {
    id: calculated_order_id
  }
  
  commit_response = client.query(commit_query, variables: commit_variables)
  
  if commit_response&.data&.order_edit_commit&.user_errors&.any?
    errors = commit_response.data.order_edit_commit.user_errors
    error_messages = errors.map { |e| e.message }.join(", ")
    puts "❌ Error committing order: #{error_messages}"
    return { success: false, error: error_messages }
  end
  
  puts "✅ Order successfully committed!"
  {
    success: true,
    calculated_order_id: calculated_order_id,
    order_id: commit_response&.data&.order_edit_commit&.order&.id
  }
rescue => e
  puts "❌ Exception occurred: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  { success: false, error: e.message }
end

# Example usage:
# shop = Shop.find_by(shopify_domain: 'your-shop.myshopify.com')
# add_variant_to_order(shop, 123456789, 987654321, 2)


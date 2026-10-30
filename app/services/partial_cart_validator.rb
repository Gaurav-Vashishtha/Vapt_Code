# app/services/partial_cart_validator.rb
class PartialCartValidator
  
    def self.validate(input_cart, cart_rule_id, shop)
      new(input_cart, cart_rule_id, shop).validate
    end
    
    def initialize(input_cart, cart_rule_id, shop)
      @input_cart = input_cart
      @cart_rule_id = cart_rule_id
      @shop = shop
      @validation_errors = []
    end
    
    def validate
      validate_cart_structure
      validate_global_rules
      validate_individual_items
      
      if @validation_errors.any?
        {
          valid: false,
          error: "Cart validation failed - #{@validation_errors.count} error(s) found",
          details: @validation_errors
        }
      else
        { valid: true }
      end
    end
    
    private
    
    def validate_cart_structure
      unless @input_cart.is_a?(Array)
        add_global_error("inputCart must be an array")
        return
      end
      
      if @input_cart.empty?
        add_global_error("inputCart cannot be empty")
        return
      end
      
      if @input_cart.length > 50 # Reasonable limit
        add_global_error("inputCart cannot contain more than 50 items")
      end
    end
    
    def validate_global_rules
      # Can't mix cart rule with individual rules
      if @cart_rule_id.present? && @input_cart.any? { |item| item['ruleId'].present? }
        add_global_error("Cannot mix cartRuleId with individual item ruleIds")
      end
      
      # Validate cart rule exists if provided
      if @cart_rule_id.present?
        cart_rule = PartialRuleSet.find_by(id: @cart_rule_id, is_cart_rule: true, shop_id: @shop.id)
        if cart_rule.blank?
          add_global_error("cartRuleId #{@cart_rule_id} not found or is not a cart rule for this shop")
        elsif !cart_rule.is_enabled?
          add_global_error("cartRuleId #{@cart_rule_id} is disabled")
        end
      end
    end
    
    def validate_individual_items
      @input_cart.each_with_index do |cart_item, index|
        validate_item(cart_item, index)
      end
    end
    
    def validate_item(cart_item, index)
      item_errors = []
      
      # Required fields
      item_errors << "variantId is required" if cart_item['variantId'].blank?
      item_errors << "title is required" if cart_item['title'].blank?
      
      # Quantity validation
      quantity = cart_item['totalQuantity'] || cart_item['quantity']
      if quantity.blank? || quantity.to_i <= 0
        item_errors << "totalQuantity must be a positive number"
      elsif quantity.to_i > 999
        item_errors << "totalQuantity cannot exceed 999"
      end
      
      # Rule and cost validation
      has_rule = cart_item['ruleId'].present? || @cart_rule_id.present?
      
      if has_rule
        validate_item_with_rule(cart_item, item_errors)
      else
        validate_item_without_rule(cart_item, item_errors)
      end
      
      # Add item errors to main validation
      if item_errors.any?
        @validation_errors << {
          item_index: index,
          variant_id: cart_item['variantId'],
          title: cart_item['title'],
          errors: item_errors
        }
      end
    end
    
    def validate_item_with_rule(cart_item, item_errors)
      # Cost is REQUIRED for items with rules
      if cart_item['cost'].blank?
        item_errors << "cost is required for items with rules"
        return
      end
      
      # Validate cost format and value
      cost = parse_cost(cart_item['cost'])
      if cost.nil?
        item_errors << "cost must be a valid number"
        return
      end
      
      if cost < 0
        item_errors << "cost cannot be negative"
        return
      end
      
      # Special validation for $0 costs
      if cost == 0
        zero_validation = validate_zero_cost_rule(cart_item)
        unless zero_validation[:valid]
          item_errors << zero_validation[:error]
        end
      end
      
      # Validate individual rule if specified
      if cart_item['ruleId'].present?
        validate_individual_rule(cart_item['ruleId'], item_errors)
      end
    end
    
    def validate_item_without_rule(cart_item, item_errors)
      # Items without rules can have cost but it's optional
      if cart_item['cost'].present?
        cost = parse_cost(cart_item['cost'])
        if cost.nil?
          item_errors << "cost must be a valid number when provided"
        elsif cost < 0
          item_errors << "cost cannot be negative"
        end
      end
    end
    
    def validate_individual_rule(rule_id, item_errors)
      rule = PartialRuleSet.find_by(id: rule_id, shop_id: @shop.id)
      
      if rule.blank?
        item_errors << "ruleId #{rule_id} not found for this shop"
      elsif rule.is_cart_rule?
        item_errors << "ruleId #{rule_id} is a cart rule, not an individual item rule"
      elsif !rule.is_enabled?
        item_errors << "ruleId #{rule_id} is disabled"
      end
    end
    
    def validate_zero_cost_rule(cart_item)
      rule_id = cart_item['ruleId'] || @cart_rule_id
      
      unless rule_id.present?
        return {
          valid: false,
          error: "cost cannot be $0 without a valid rule"
        }
      end
      
      rule_set = PartialRuleSet.find_by(id: rule_id, shop_id: @shop.id)
      unless rule_set
        return {
          valid: false,
          error: "rule not found for $0 cost validation"
        }
      end
      
      # Check if rule allows $0 cost
      allows_zero = (
        rule_set.amount.to_f == 0 ||
        (rule_set.amount_type == 'percentage' && rule_set.amount.to_f == 0) ||
        (rule_set.amount_type == 'fixed' && rule_set.amount.to_f == 0)
      )
      
      unless allows_zero
        return {
          valid: false,
          error: "cost cannot be $0 for rule '#{rule_set.rule_name}' (#{rule_set.amount_type}: #{rule_set.amount})"
        }
      end
      
      { valid: true }
    end
    
    def parse_cost(cost_value)
      return nil if cost_value.blank?
      
      if cost_value.is_a?(String)
        # Remove currency symbols and clean
        cleaned_cost = cost_value.gsub(/[^\d.]/, '')
        return nil if cleaned_cost.blank?
        cleaned_cost.to_f
      elsif cost_value.is_a?(Numeric)
        cost_value.to_f
      else
        nil
      end
    rescue
      nil
    end
    
    def add_global_error(message)
      @validation_errors << {
        global: true,
        errors: [message]
      }
    end
  end
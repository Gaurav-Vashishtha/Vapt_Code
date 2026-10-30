# app/models/cod_king_stat.rb
class CodKingStat < ApplicationRecord
    validates :stat_key, presence: true
    validates :stat_value, presence: true, numericality: { only_integer: true }
    validates :stat_date, presence: true
    
    # Scopes for common queries
    scope :for_date, ->(date) { where(stat_date: date) }
    scope :for_key, ->(key) { where(stat_key: key) }
    scope :for_date_range, ->(start_date, end_date) { where(stat_date: start_date..end_date) }
    
    # Main method to update or create stats
    def self.update_stat(stat_key, value, description: nil, operation: :increment, stat_date: Date.current)
      # Find existing record or initialize new one
      stat_record = find_or_initialize_by(
        stat_key: stat_key,
        stat_date: stat_date
      )
      
      if stat_record.persisted?
        # Record exists, apply operation based on type
        case operation
        when :update, :set
          # Set absolute value
          stat_record.stat_value = value.to_i
        when :increment, :add
          # Add to existing value
          stat_record.stat_value += value.to_i
        else
          # Default to increment for unknown operations
          stat_record.stat_value += value.to_i
        end
      else
        # New record, set initial values
        stat_record.stat_value = value.to_i
        stat_record.description = description if description.present?
      end
      
      # Update description if provided
      stat_record.description = description if description.present?
      
      # Save and return the record
      stat_record.save!
      stat_record
    end
    
    # Convenience method for incrementing
    def self.increment_stat(stat_key, value = 1, description: nil, stat_date: Date.current)
      update_stat(stat_key, value, description: description, operation: :increment, stat_date: stat_date)
    end
    
    # Convenience method for setting absolute value
    def self.set_stat(stat_key, value, description: nil, stat_date: Date.current)
      update_stat(stat_key, value, description: description, operation: :set, stat_date: stat_date)
    end
    
    # Alternative implementation based on value type detection
    def self.update_stat_auto(stat_key, value, description: nil)
      current_date = Date.current
      
      stat_record = find_or_initialize_by(
        stat_key: stat_key,
        stat_date: current_date
      )
      
      if stat_record.persisted?
        # If value is negative or explicitly marked for increment (you can customize this logic)
        if value.is_a?(String) && value.start_with?('+')
          # Increment mode: "+5" means add 5
          increment_value = value[1..-1].to_i
          stat_record.stat_value += increment_value
        elsif value.to_i < 0
          # Negative values are treated as decrements
          stat_record.stat_value += value.to_i
        else
          # Positive integers are treated as absolute values
          stat_record.stat_value = value.to_i
        end
      else
        # New record
        initial_value = value.is_a?(String) && value.start_with?('+') ? value[1..-1].to_i : value.to_i
        stat_record.stat_value = initial_value
        stat_record.description = description if description.present?
      end
      
      stat_record.description = description if description.present?
      stat_record.save!
      stat_record
    end
    
    # Get stats for a specific key and date range
    def self.get_stats_for_period(stat_key, start_date = 30.days.ago.to_date, end_date = Date.current)
      for_key(stat_key)
        .for_date_range(start_date, end_date)
        .order(:stat_date)
    end
    
    # Get latest stat value for a key
    def self.latest_value_for_key(stat_key)
      for_key(stat_key)
        .order(stat_date: :desc)
        .limit(1)
        .pluck(:stat_value)
        .first || 0
    end
    
    # Get today's stats summary
    def self.today_summary
      for_date(Date.current)
        .select(:stat_key, :stat_value, :description)
        .order(:stat_key)
    end
  end
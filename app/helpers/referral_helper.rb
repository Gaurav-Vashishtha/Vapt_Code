module ReferralHelper
    def payout_status_classes(status)
      case status.to_s
      when 'pending'
        'bg-yellow-100 text-yellow-800'
      when 'processing'
        'bg-blue-100 text-blue-800'
      when 'completed'
        'bg-green-100 text-green-800'
      when 'failed', 'cancelled'
        'bg-red-100 text-red-800'
      else
        'bg-gray-100 text-gray-800'
      end
    end
  
    def earning_status_classes(status)
      case status.to_s
      when 'unpaid'
        'bg-yellow-100 text-yellow-800'
      when 'pending_payout'
        'bg-blue-100 text-blue-800'
      when 'paid'
        'bg-green-100 text-green-800'
      else
        'bg-gray-100 text-gray-800'
      end
    end
  
    def format_currency(amount, currency = 'USD')
      number_to_currency(amount, unit: currency == 'USD' ? '$' : currency)
    end
  
    def format_commission_rate(rate)
      "#{number_with_precision(rate, precision: 2)}%"
    end
  
    def sync_status_badge(shop)
      if shop.historical_sync_completed?
        content_tag :span, 'Synced', class: 'px-2 py-1 text-xs font-medium rounded-full bg-green-100 text-green-800'
      else
        content_tag :span, 'Needs Historical Sync', class: 'px-2 py-1 text-xs font-medium rounded-full bg-yellow-100 text-yellow-800'
      end
    end
  
    def payout_method_icon(method)
      case method
      when 'bank_transfer'
        content_tag :svg, class: "w-4 h-4 text-gray-600", fill: "currentColor", viewBox: "0 0 20 20" do
          content_tag :path, nil, d: "M4 4a2 2 0 00-2 2v1h16V6a2 2 0 00-2-2H4zM18 9H2v5a2 2 0 002 2h12a2 2 0 002-2V9zM4 13a1 1 0 011-1h1a1 1 0 110 2H5a1 1 0 01-1-1zm5-1a1 1 0 100 2h1a1 1 0 100-2H9z"
        end
      when 'paypal'
        content_tag :svg, class: "w-4 h-4 text-blue-600", fill: "currentColor", viewBox: "0 0 20 20" do
          content_tag :path, nil, "fill-rule": "evenodd", d: "M4 4a2 2 0 00-2 2v8a2 2 0 002 2h12a2 2 0 002-2V6a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z", "clip-rule": "evenodd"
        end
      else
        ''
      end
    end
  
    def last_sync_display(date)
      return 'Never' unless date
      
      if date >= 1.day.ago.to_date
        'Today'
      elsif date >= 1.week.ago.to_date
        "#{distance_of_time_in_words(date, Date.current)} ago"
      else
        date.strftime('%Y-%m-%d')
      end
    end
  
    def earnings_summary_by_type(earnings)
      summary = earnings.group(:transaction_type).sum(:commission_amount)
      {
        subscription: summary['subscription'] || 0,
        usage: summary['usage'] || 0,
        onetime: summary['onetime'] || 0
      }
    end
  
    def payout_eligibility_text(partner)
      return "Account not verified" unless partner.account_verified?
      
      unpaid_amount = partner.total_unpaid_earnings
      minimum_payout = 50.0
      
      if unpaid_amount >= minimum_payout
        "Eligible for payout"
      else
        "Need $#{number_with_precision(minimum_payout - unpaid_amount, precision: 2)} more"
      end
    end
  
    def next_payout_date_estimate
      today = Date.current
      if today.day <= 15
        Date.new(today.year, today.month, 15)
      else
        next_month = today.next_month
        Date.new(next_month.year, next_month.month, 15)
      end
    end
  
    def commission_trend_arrow(current, previous)
      return '' if previous.zero?
      
      percentage_change = ((current - previous) / previous * 100).round(1)
      
      if percentage_change > 0
        content_tag :span, class: "text-green-600" do
          "↗ +#{percentage_change}%"
        end
      elsif percentage_change < 0
        content_tag :span, class: "text-red-600" do
          "↘ #{percentage_change}%"
        end
      else
        content_tag :span, class: "text-gray-600" do
          "→ 0%"
        end
      end
    end
  end
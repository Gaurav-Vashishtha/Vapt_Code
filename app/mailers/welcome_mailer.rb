# require 'sendgrid-ruby'
# include SendGrid

class WelcomeMailer < ApplicationMailer
  layout 'mailer'
  def first_time(sender_mail, params)
    @shopify_domain = params[:shopify_domain]
    @name = params[:name]
    @user_email = sender_mail
    crisp_url_init(sender_mail)
    mail(to: sender_mail, subject: "Welcome! You're one step away to streamline your COD verification")
  end

  def easy_sell_usage_count(emails,usage_count)
    @usage_count = usage_count
    mail(to: emails, subject: "OTP SMS count COD King")
  end

  def plan_upgrade(sender_mail, params)
    @name = params[:name]
    @owner_name = params[:owner_name]
    @shopify_domain = params[:shopify_domain]
    crisp_url_init(sender_mail)
    mail(to: sender_mail, subject: 'Thank you for upgrading to COD King!')
  end

  def request_feedback(sender_mail)
    mail(to: sender_mail, subject: 'Wish Connect - Request For Feedback')
  end

  def uninstall_feedback(sender_mail, params)
    @shopify_domain = params[:shopify_domain]
    @checkout_settings_url = "https://#{@shopify_domain}/admin/settings/checkout"
    @name = params[:name]
    @user_email = sender_mail
    @survey_url = params[:survey_url]
    crisp_url_init(sender_mail)
    mail(to: sender_mail, subject: "#{params[:owner_name]} - Offer just for you!")
  end

  def feature_update(shop_id)
    shop = Shop.find(shop_id)
    @shopify_domain = shop.shopify_domain
    @name = shop.shop_owner
    @shop_name = shop.owner_name
    sender_mail = shop.owner_email
    crisp_url_init(sender_mail)
    mail(to: sender_mail, subject: "Major Product Update - Wish Connect!")
  end

  def send_csv(shop_id)
    shop = Shop.find(shop_id)
    csv = shop.order_confirmations.last_2_months.to_csv
    @shopify_domain = shop.shopify_domain
    @name = shop.shop_owner
    @shop_name = shop.owner_name
    crisp_url_init(shop.owner_email)
    attachments["orders-#{Date.today}.csv"] = { mime_type: 'text/csv', content: csv }
    mail(to: shop.owner_email, subject: "COD King Export | #{Date.today}")
  end

  def format_date(date)
    date.strftime('%b %d, %l:%M %p')
  end


  def referral_partner_signup(partner_id, plain_password = nil)
    @partner = ReferralPartner.find(partner_id)
    @name = @partner.name
    @email = @partner.email
    @password = plain_password # Store the plain password to include in email
    @referral_code = @partner.referral_code
    @login_url = referral_login_url(**referral_program_mailer_url_options)

    mail(
      to: @partner.email,
      subject: "Welcome to COD King Referral Program - #{@partner.name}!",
      layout: false
    )
  end

  def referral_partner_created_admin_notification(partner_id)
    @partner = ReferralPartner.find(partner_id)
    @admin_panel_url = referral_admin_referral_partners_url(**referral_program_mailer_url_options)
    
    mail(
      to: ENV.fetch("WHATSAPP_APPROVERS_EMAIL_LIST", nil) || 'adbhatia1989@gmail.com,support@notifiktech.com', # Set your admin email
      subject: "New Referral Partner Signup - #{@partner.name}"
    )
  end



  def send_message_logs_csv(shop_id, days)
    shop = Shop.find(shop_id)
    days = days.to_i > 0 ? days.to_i : 30 # fallback to 30 days
    from_date = Time.current - days.days
  
    # Extract IANA timezone from string like "(GMT-05:00) America/New_York"
    def extract_iana_timezone(tz_string)
      tz_string.to_s.split(')').last.strip rescue "UTC"
    end
  
    # Format cart items
    def format_cart_items(cart_details)
      return "" unless cart_details.is_a?(Array)
  
      cart_details.map do |item|
        title = item['title'].to_s.gsub(/^Partial Payment for /, '').strip
        quantity = item['quantity'].to_s.presence || "1"
        price = item['price'].to_f
        price_in_rs = price > 1000 ? (price / 100.0).round : price
  
        "#{quantity} x #{title} - ₹#{price_in_rs}"
      end.join("; ")
    end
  
    owner_tz_name = extract_iana_timezone(shop.owner_timezone)
    owner_timezone = ActiveSupport::TimeZone[owner_tz_name] || ActiveSupport::TimeZone["UTC"]
  
    # Abandoned carts
    abandoned_carts = shop.abandoned_carts
      .where("shopify_created_at >= ?", from_date)
      .select('status, phone as customer_number, country_code, shopify_created_at as created_at')
      .order('shopify_created_at DESC')
      .to_a
      .map { |r| r.attributes.symbolize_keys.merge(source: :abandoned_cart) }
  
    # Pre-order OTPs
    pre_order_otps = shop.pre_order_otps.otp_sends
      .where("created_at >= ?", from_date)
      .select('status,order_status, phone as customer_number, country_code, created_at, cart_details, verification_status')
      .order('created_at DESC')
      .to_a
      .map { |r| r.attributes.symbolize_keys.merge(source: :pre_order_otp) }
  
    # Order Confirmations with Twilio logs
    order_confirmations_with_twilio_logs = shop.order_confirmations
      .joins(:twilio_logs)
      .where("twilio_logs.created_at >= ?", from_date)
      .select('order_confirmations.order_id, twilio_logs.ver_type, twilio_logs.country_code, twilio_logs.customer_number, twilio_logs.created_at, twilio_logs.status')
      .order('twilio_logs.created_at DESC')
      .to_a
      .map { |r| r.attributes.symbolize_keys.merge(source: :order_confirmation) }
  
    message_logs = abandoned_carts + pre_order_otps + order_confirmations_with_twilio_logs
    message_logs.sort_by! { |log| log[:created_at] || Time.at(0) }
    message_logs.reverse!
  
    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["Shopify Order ID", "Sent Date & Time", "Phone Number", "Country", "Status", "Cart Items", "Checkout Status", "Verification Status"]
  
      message_logs.each do |log|
        created_at_utc = log[:created_at]
        created_at_in_owner_tz = created_at_utc ? owner_timezone.at(created_at_utc) : nil
  
        status = case log[:source]
                 when :pre_order_otp
                   log[:status] == true ? "SUCCESS (PRE-ORDER-OTP)" : "FAILED (PRE-ORDER-OTP)"
                 when :abandoned_cart
                   "#{log[:status]} (ABANDONED-CHECKOUT)"
                 when :order_confirmation
                   log[:status]
                 else
                   log[:status].to_s
                 end
  
        cart_items = ""
        checkout_status = ""
        if log[:source] == :pre_order_otp
          checkout_status = log[:order_status]
          begin
            raw_cart_details = log[:cart_details]
  
            cart_details =
              if raw_cart_details.is_a?(Array)
                if raw_cart_details.first.is_a?(String)
                  pairs = raw_cart_details.map do |entry|
                    key, value = entry.split('=>', 2)
                    [key.to_s.strip, value.to_s.strip] if key && value
                  end.compact
  
                  cart_items_array = []
                  pairs.each_slice(4) { |item_pairs| cart_items_array << item_pairs.to_h }
                  cart_items_array
                elsif raw_cart_details.first.is_a?(Hash)
                  raw_cart_details
                else
                  []
                end
              else
                []
              end
  
            cart_items = format_cart_items(cart_details)
          rescue => e
            cart_items = ""
            puts "❌ Cart parse error for #{log[:customer_number]}: #{e.message}"
          end
        end
  
        verification_status = log[:verification_status] || ""
  
        csv << [
          log[:order_id],
          created_at_in_owner_tz ? created_at_in_owner_tz.strftime("%d-%b-%Y %I:%M %p") : "",
          log[:customer_number],
          log[:country_code],
          status,
          cart_items,
          checkout_status,
          verification_status
        ]
      end
    end
  
    @shopify_domain = shop.shopify_domain
    @name = shop.shop_owner
    @shop_name = shop.owner_name
    crisp_url_init(shop.owner_email)
  
    attachments["orders-#{Date.today}.csv"] = { mime_type: 'text/csv', content: csv_data }
    mail(to: shop.owner_email, subject: "COD King Export | #{Date.today}")
  end
  
  
  
  
  
  

  def send_whatsapp_approval_request(shop_id)
    shop = Shop.find(shop_id)
    @shopify_domain = shop.shopify_domain
    @shop_id = shop.id
    @name = shop.shop_owner
    @shop_name = shop.owner_name
    crisp_url_init(shop.owner_email)
    mail(
      to: shop.owner_email,
      cc: ENV.fetch("WHATSAPP_APPROVERS_EMAIL_LIST", nil),
      subject: "WhatsApp Approval Request | #{Date.today}"
    )
  end


  

  def free_sender_id_ae(shop_id)
    shop = Shop.find(shop_id)
    @shopify_domain = shop.shopify_domain
    @shop_id = shop.id
    @name = shop.shop_owner
    @shop_name = shop.owner_name
    crisp_url_init(shop.owner_email)
    mail(
      to: shop.owner_email,
      cc: ENV.fetch("WHATSAPP_APPROVERS_EMAIL_LIST", nil),
      subject: "Free upgrade to Branded SMS - Sender ID registeration - COD King"
    )
  end


  def send_whatsapp_approval_confirmation(shop_id)
    shop = Shop.find(shop_id)
    @shopify_domain = shop.shopify_domain
    @shop_id = shop.id
    @name = shop.shop_owner
    @shop_name = shop.owner_name
    crisp_url_init(shop.owner_email)
    mail(
      to: shop.owner_email,
      cc: ENV.fetch("WHATSAPP_APPROVERS_EMAIL_LIST", nil),
      subject: "Congratulations - COD King WhatsApp account Approved"
    )
  end

  def send_whatsapp_rejection(shop_id)
    shop = Shop.find(shop_id)
    @shopify_domain = shop.shopify_domain
    @shop_id = shop.id
    @name = shop.shop_owner
    @shop_name = shop.owner_name
    crisp_url_init(shop.owner_email)
    mail(
      to: shop.owner_email,
      bcc: ENV.fetch("WHATSAPP_APPROVERS_EMAIL_LIST", nil),
      subject: "Important - COD King WhatsApp account could not be approved "
    )
  end


  def lock_shop(shop_id)
    shop = Shop.find(shop_id)
    @shopify_domain = shop.shopify_domain
    @name = shop.shop_owner
    crisp_url_init(shop.owner_email)
    mail(to: shop.owner_email, subject: "COD King Deactivated")
  end

  def lock_cod_fee_feature(shop_id)
    shop = Shop.find(shop_id)
    @shopify_domain = shop.shopify_domain
    @name = shop.shop_owner
    crisp_url_init(shop.owner_email)
    mail(to: shop.owner_email, subject: "COD fee Deactivated")
  end

  def will_lock_cod_fee_feature(shop_id)
    shop = Shop.find(shop_id)
    @shopify_domain = shop.shopify_domain
    @name = shop.shop_owner
    crisp_url_init(shop.owner_email)
    mail(to: shop.owner_email, subject: "Action required - COD fee will be Deactivated Soon")
  end

  def lock_shop_capped_amount_exceeded(shop_id)
    shop = Shop.find(shop_id)
    @shopify_domain = "https://#{shop.shopify_domain}/admin/apps/cod-verification"
    @name = shop.shop_owner
    crisp_url_init(shop.owner_email)
    mail(to: shop.owner_email, bcc: ENV.fetch("WHATSAPP_APPROVERS_EMAIL_LIST", nil), subject: "COD King SMS/Whatsapp Locked")
  end

  def whatsapp_branding_removed_downgrade(shop_id)
    shop = Shop.find(shop_id)
    @shopify_domain = shop.shopify_domain
    @name = shop.shop_owner
    @subscription_url = "https://#{shop.shopify_domain}/admin/apps/cod-verification/subscription"
    crisp_url_init(shop.owner_email)
    mail(to: shop.owner_email, subject: "COD King – WhatsApp branding removed due to plan change")
  end

  def whatsapp_branding_removed_admin_notification(shop_id, previous_whatsapp_number)
    shop = Shop.find(shop_id)
    @shopify_domain = shop.shopify_domain
    @shop_name = shop.owner_name.presence || shop.shopify_domain
    @previous_whatsapp_number = previous_whatsapp_number
    approver_emails = ENV.fetch("WHATSAPP_APPROVERS_EMAIL_LIST", nil).to_s.strip
    approver_emails = 'support@notifiktech.com' if approver_emails.blank?
    mail(to: approver_emails, subject: "COD King – Remove WhatsApp number from Operator (#{shop.shopify_domain})")
  end

  def sms_template_submission_owner(approval_id)
    @approval = SmsTemplateApproval.includes(:shop).find(approval_id)
    @shop = @approval.shop
    @shopify_domain = @shop.shopify_domain
    @name = @shop.shop_owner
    @shop_name = @shop.owner_name
    crisp_url_init(@shop.owner_email)

    mail(
      to: @shop.owner_email,
      subject: "SMS template submitted for approval | #{Date.today}"
    )
  end

  def sms_template_submission_admin(approval_id)
    @approval = SmsTemplateApproval.includes(:shop).find(approval_id)
    @shop = @approval.shop
    @shopify_domain = @shop.shopify_domain
    @name = @shop.shop_owner
    @shop_name = @shop.owner_name
    crisp_url_init(@shop.owner_email)

    approver_emails = ENV.fetch("WHATSAPP_APPROVERS_EMAIL_LIST", nil).to_s.strip
    approver_emails = "support@notifiktech.com" if approver_emails.blank?

    mail(
      to: approver_emails,
      subject: "Action required: SMS template approval request (#{@shop.shopify_domain})"
    )
  end


  private
  def crisp_url_init(sender_mail)
    token = Digest::MD5.hexdigest(@shopify_domain)
    @crisp_url="https://go.crisp.chat/chat/embed/?website_id=#{ENV.fetch("CRISP_WEBSITE_ID", nil)}&user_email=#{sender_mail}&user_nickname=#{@name}&token_id=#{token}"
  end
end

# WelcomeMailer.plan_upgrade(@shop.owner_email, {name: @shop.shop_owner, shopify_domain: @shop.shopify_domain, owner_name: @shop.owner_name}).deliver_now

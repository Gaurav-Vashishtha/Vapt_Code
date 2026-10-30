module Whatsapp
  # Turns a campaign's variable_mapping + a recipient's fields into the
  # body/header/button parameters the Meta send service expects. Mapping is
  # `{ "1" => "cart.name", "2" => "csv.coupon" }`; field values come from the
  # recipient row captured at snapshot time. Blank values fall back to the
  # campaign's per-variable defaults (`variable_defaults`).
  module CampaignMessageBuilder
    module_function

    def body_parameters(campaign, recipient)
      template = campaign.whatsapp_template
      fields = field_lookup(recipient)
      body_positions(template).map do |position|
        { 'type' => 'text', 'text' => resolve(campaign, fields, position) }
      end
    end

    def button_slug(campaign, recipient)
      return nil if campaign.button_field.blank?
      field_lookup(recipient)[campaign.button_field].to_s.presence
    end

    def header_parameters(campaign, template, recipient = nil)
      if header_text_variable?(template)
        value = recipient ? field_lookup(recipient)[campaign.header_field].to_s.strip : ''
        value = campaign_defaults(campaign)['header'].to_s.strip if value.blank? && !skip_on_missing?(campaign)
        return value.present? ? [{ 'type' => 'text', 'text' => value }] : nil
      end

      media = template.media_header_param(nil, campaign.shop)
      media ? [media] : nil
    rescue StandardError
      nil
    end

    # Every template parameter Meta requires at send time that this recipient
    # cannot fill (no field value and no default). A non-empty result means the
    # send would fail with #131008, so callers skip/suppress instead.
    def missing_values(campaign, recipient)
      template = campaign.whatsapp_template
      return [] unless template

      fields = field_lookup(recipient)
      missing = body_positions(template).filter_map do |position|
        "{{#{position}}} (#{campaign.variable_mapping&.dig(position.to_s) || 'unmapped'})" if resolve(campaign, fields, position).blank?
      end

      if header_text_variable?(template) && Array(header_parameters(campaign, template, recipient)).empty?
        missing << "header (#{campaign.header_field.presence || 'unmapped'})"
      end

      if dynamic_url_button?(template) && button_slug(campaign, recipient).blank?
        missing << "url button (#{campaign.button_field.presence || 'unmapped'})"
      end

      missing
    end

    # The final URL the recipient's button will open, for previews/test results.
    # Static URLs pass through; dynamic ones ({{1}}) get the slug substituted.
    def button_url(campaign, recipient)
      template = campaign.whatsapp_template
      buttons = Array(template&.components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('BUTTONS') }
      button = Array(buttons.to_h['buttons']).find { |b| b.is_a?(Hash) && b['type'].to_s.casecmp?('URL') }
      return nil unless button

      url = button['url'].to_s
      return url unless url.include?('{{')

      slug = button_slug(campaign, recipient)
      slug.present? ? url.gsub(/\{\{\d+\}\}/, slug) : nil
    end

    def skip_on_missing?(campaign)
      campaign.respond_to?(:missing_value_policy) && campaign.missing_value_policy == 'skip'
    end

    def body_positions(template)
      body = Array(template&.components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('BODY') }
      body.to_h['text'].to_s.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).uniq.sort
    end

    def header_text_variable?(template)
      header = Array(template&.components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('HEADER') }
      return false unless header && header['format'].to_s.casecmp?('TEXT')
      header['text'].to_s.match?(/\{\{\d+\}\}/)
    end

    def dynamic_url_button?(template)
      buttons = Array(template&.components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('BUTTONS') }
      Array(buttons.to_h['buttons']).any? do |b|
        b.is_a?(Hash) && b['type'].to_s.casecmp?('URL') && b['url'].to_s.include?('{{')
      end
    end

    def resolve(campaign, fields, position)
      key = campaign.variable_mapping&.dig(position.to_s)
      value = key.present? ? format_value(fields[key]) : ''
      return value if value.present? || skip_on_missing?(campaign)
      campaign_defaults(campaign)[position.to_s].to_s.strip
    end

    def campaign_defaults(campaign)
      campaign.respond_to?(:variable_defaults) && campaign.variable_defaults.is_a?(Hash) ? campaign.variable_defaults : {}
    end

    def field_lookup(recipient)
      base = (recipient.fields || {}).dup
      base['recipient.name'] = recipient.name
      base['recipient.phone'] = recipient.phone
      base['recipient.email'] = recipient.email
      base
    end

    def format_value(value)
      return '' if value.nil?
      value.to_s.gsub(/[\r\n\t]+/, ' ').strip
    end
  end
end

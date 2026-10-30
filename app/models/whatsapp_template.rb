class WhatsappTemplate < ApplicationRecord
  # Guaranteed-public https image used as the last-resort header for IMAGE
  # templates when nothing else resolves. An approved image template REQUIRES a
  # header image; sending without one makes Meta reject the whole message. A
  # branded fallback is always better than a failed delivery.
  DEFAULT_HEADER_IMAGE_URL =
    "https://cdn.shopify.com/s/files/1/0655/2089/4070/files/with_bg_logo2.png?v=1770038556".freeze

  belongs_to :whatsapp_account
  has_one :shop, through: :whatsapp_account
  # A template can back MULTIPLE bindings (uniqueness is per shop+event+stage,
  # not per template — e.g. every abandoned-cart stage bound to one template).
  # This was has_one dependent: :destroy, which removed only one binding row on
  # template destroy and left the rest violating fk_rails_6b9cf0b2a6, aborting
  # the whole shop.destroy cascade during uninstall.
  has_many :bindings, class_name: 'WhatsappTemplateBinding', dependent: :destroy

  def binding
    bindings.first
  end
  # Logs survive template deletion — the FK is `ON DELETE SET NULL` (see
  # migration 20260611140000). Rails-level `dependent: :nullify` mirrors that
  # behaviour for callsites that use the association before the SQL fires.
  has_many :whatsapp_message_logs, dependent: :nullify
  has_one :custom_branded_template_event, dependent: :destroy

  enum status: {
    pending: 0,
    approved: 1,
    rejected: 2,
    paused: 3,
    disabled: 4
  }

  enum category: {
    utility: 'UTILITY',
    marketing: 'MARKETING',
    authentication: 'AUTHENTICATION'
  }

  validates :name, presence: true, format: { with: /\A[a-z0-9_]+\z/, message: 'must be lowercase alphanumeric with underscores' }
  validates :language, presence: true
  validates :name, uniqueness: { scope: %i[whatsapp_account_id language] }
  validate :event_type_must_exist
  validate :category_matches_event_type
  validate :url_button_is_well_formed
  validate :cod_verification_buttons_mappable, if: -> { %w[cod_verification cod_verification_reminder].include?(event_type_key.to_s) && will_save_change_to_event_type_key? }

  scope :approved_for, ->(event_type_key) { approved.where(event_type_key: event_type_key) }

  def bound?
    bindings.exists?
  end

  def url_button_present?
    url_button.is_a?(Hash) && url_button['mode'].present?
  end

  # Returns the Meta send-time `header` component parameter for IMAGE/VIDEO/
  # DOCUMENT templates, or nil if (a) the header isn't a media format, or
  # (b) the template has no send-usable media reference.
  #
  # Resolution order:
  #   1. header_media.mode == 'order_product_image' → resolve from payload
  #      (first line item's image URL); falls through to example_url if the
  #      payload can't yield an image so the dispatch still sends something.
  #   2. header_media.media_id        → image.id   (Cloud API media upload)
  #   3. header_media.url             → image.link
  #   4. header_media.value (legacy)  → image.link if source==url, else skip
  #   5. components[HEADER].example.header_handle if it's a URL → image.link
  #
  # Resumable-upload handles (`4::...`) are never returned because Meta
  # rejects them at send time.
  #
  # `payload` is the dispatch payload (order/checkout hash). It's only needed
  # when header_media.mode is a dynamic source like 'order_product_image';
  # static modes ignore it, which keeps every existing call site working.
  # `shop` is needed to do the Shopify API lookup for the line item's product
  # image — Shopify order webhooks don't embed line-item images, so the
  # resolver has to fetch them when running for an order event.
  # Template review sample URLs (scontent.whatsapp.net / fbcdn) are signed and expire
  # within hours; Meta accepts a send that uses one, then silently fails delivery
  # when it can't fetch the image.
  META_SAMPLE_HOSTS = /(\A|\.)(whatsapp\.net|fbcdn\.net|fbsbx\.com)\z/i

  def meta_sample_link?(url)
    host = URI.parse(url.to_s).host.to_s
    host.match?(META_SAMPLE_HOSTS)
  rescue URI::InvalidURIError
    false
  end

  def media_header_param(payload = nil, shop = nil)
    header = Array(components).find { |c| c.is_a?(Hash) && c['type'].to_s.casecmp?('HEADER') }
    return nil unless header

    format = header['format'].to_s.upcase
    return nil unless %w[IMAGE VIDEO DOCUMENT].include?(format)

    kind = format.downcase
    hm = header_media.is_a?(Hash) ? header_media : {}

    inner =
      if hm['mode'] == 'order_product_image'
        url = Whatsapp::OrderProductImageResolver.call(
          payload: payload,
          event_type_key: event_type_key,
          shop: shop || whatsapp_account&.shop
        )
        # Fall back to the static example_url chosen at create time so we don't
        # nil out the header just because the payload happened not to have a
        # product image (e.g. a tip-only order, an order with deleted products).
        url ||= hm['example_url']
        resolve_order_product_image(url)
      elsif hm['media_id'].present?
        { 'id' => hm['media_id'] }
      elsif hm['url'].present?
        { 'link' => hm['url'] }
      elsif hm['source'] == 'url' && hm['value'].present?
        { 'link' => hm['value'] }
      else
        handle = header.dig('example', 'header_handle')&.first
        { 'link' => handle } if handle.present? && handle.start_with?('http') && !meta_sample_link?(handle)
      end

    # Last-resort fallback for IMAGE headers: an unbound event, a sample/test
    # payload, or an order without a usable product image all leave `inner` nil,
    # which would drop the header component and make Meta reject the send. Image
    # templates can safely fall back to a branded image; video/document can't, so
    # they still return nil.
    if inner.nil? && format == 'IMAGE'
      fallback = image_header_fallback_url(shop)
      inner = { 'link' => fallback } if fallback.present?
    end

    return nil unless inner
    { 'type' => kind, kind => inner }
  end

  private

  # JPEG/PNG go out as a `link` (SendTemplateMessageService pre-uploads them at
  # send time). Meta can't fetch a HEIC/WebP link, so those are transcoded to
  # JPEG and uploaded here as a media_id; a nil result drops to the branded
  # logo fallback rather than shipping a link Meta will reject.
  def resolve_order_product_image(url)
    if Whatsapp::OrderProductImageResolver.supported_image_url?(url)
      { 'link' => url }
    elsif Whatsapp::OrderProductImageResolver.convertible_image_url?(url)
      media_id = Whatsapp::HeaderImageUploader.call(account: whatsapp_account, url: url)
      { 'id' => media_id } if media_id.present?
    end
  end

  # A guaranteed-reachable https image for IMAGE headers with no resolved media:
  # the shop's own brand logo if set, otherwise the app default. Only http(s)
  # URLs qualify — a relative/blank logo would itself be rejected by Meta.
  def image_header_fallback_url(shop)
    shop ||= whatsapp_account&.shop
    logo = shop&.setting&.brand_logo_url
    # Skip an SVG/webp brand logo — it would 131053 just like an SVG product
    # image. Only a JPG/PNG logo is a safe header; otherwise the app default.
    return logo if Whatsapp::OrderProductImageResolver.supported_image_url?(logo)

    DEFAULT_HEADER_IMAGE_URL
  end

  def event_type_must_exist
    return if event_type_key.blank?
    return if Whatsapp::EventRegistry.find(event_type_key)
    errors.add(:event_type_key, 'is not a known event type')
  end

  def category_matches_event_type
    return if event_type_key.blank? || category.blank?
    allowed = Whatsapp::EventRegistry.bindable_categories_for(event_type_key)
    return if allowed.empty?
    # `category` (enum reader) returns the lowercase key (e.g. "utility");
    # registry returns Meta API values (e.g. "UTILITY"). Compare case-insensitively.
    return if allowed.any? { |c| c.to_s.casecmp?(category.to_s) }
    errors.add(:category, "must be one of #{allowed.join(', ')} for event #{event_type_key}")
  end

  def cod_verification_buttons_mappable
    error = Whatsapp::CodVerificationButtons.mapping_error(components)
    errors.add(:base, error) if error
  end

  def url_button_is_well_formed
    return if url_button.blank?
    unless url_button.is_a?(Hash)
      errors.add(:url_button, 'must be an object')
      return
    end

    mode = url_button['mode']
    case mode
    when 'predefined'
      var_key = url_button['variable']
      var = Whatsapp::EventRegistry.variable(event_type_key, var_key)
      if var.nil? || var[:kind] != :url
        errors.add(:url_button, "variable #{var_key.inspect} is not a URL variable for event #{event_type_key}")
      end
    when 'base'
      base = url_button['base'].to_s
      errors.add(:url_button, 'base must start with https://') unless base.start_with?('https://')
      errors.add(:url_button, 'base must not contain {{...}} placeholders') if base.include?('{{')
      var_key = url_button['variable']
      if Whatsapp::EventRegistry.variable(event_type_key, var_key).nil?
        errors.add(:url_button, "unknown variable #{var_key.inspect} for event #{event_type_key}")
      end
    else
      errors.add(:url_button, "unknown mode #{mode.inspect} (expected 'predefined' or 'base')")
    end
  end
end

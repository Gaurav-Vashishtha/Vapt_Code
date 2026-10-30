class WhatsappAccount < ApplicationRecord
  # Exactly one owner: a Shop (embedded-app merchants) OR a
  # CustomBrandedClient (partner-facing branded portal, /cb). The two columns
  # are mutually exclusive — see owner validation below.
  belongs_to :shop, optional: true
  belongs_to :custom_branded_client, optional: true
  has_many :whatsapp_templates, dependent: :destroy
  # Logs and customer replies outlive a disconnected number: the merchant keeps their activity
  # history and unbilled sends still get charged. The FK is `ON DELETE SET NULL`
  # (migration 20261014150000); `dependent: :nullify` does the same through Rails.
  has_many :whatsapp_message_logs, dependent: :nullify
  has_many :whatsapp_inbound_messages, dependent: :nullify


  # Bindings that explicitly route an event to THIS number. FK nullifies on
  # delete (see migration), so removing a number reverts its events to the
  # shop default rather than dangling.
  has_many :whatsapp_template_bindings, dependent: :nullify

  encrypts :system_user_token
  encrypts :registration_pin

  REGISTERED = 'registered'.freeze
  UNREGISTERED = 'unregistered'.freeze

  # Meta's phone-number `status` field. RATE_LIMITED / FLAGGED / RESTRICTED
  # numbers ARE registered on Cloud API — they're throttled, not disconnected —
  # so they must not be treated as unregistered.
  REGISTERED_PLATFORM_STATUSES = %w[CONNECTED RATE_LIMITED FLAGGED RESTRICTED].freeze
  UNREGISTERED_PLATFORM_STATUSES = %w[PENDING UNVERIFIED DISCONNECTED MIGRATED DELETED BANNED].freeze

  enum status: {
    pending_signup: 0,
    pending_verification: 1,
    verified: 2,
    disabled: 3
  }

  # phone_number_id is globally unique at Meta, but the SAME number may be
  # linked to both a COD King shop and a custom-branded client (one brand
  # using both products). So uniqueness is per owner TYPE: at most one Shop
  # row and at most one CustomBrandedClient row per phone_number_id. The DB
  # index is intentionally non-unique, so no migration is needed.
  validate :phone_number_id_unique_per_owner_type
  validate :exactly_one_owner

  scope :shop_owned,   -> { where.not(shop_id: nil) }
  scope :client_owned, -> { where.not(custom_branded_client_id: nil) }

  # The Shop or CustomBrandedClient this number belongs to.
  def owner
    shop || custom_branded_client
  end

  # Rows for the same number under the other surface (COD King <-> CB).
  def linked_accounts
    return WhatsappAccount.none if phone_number_id.blank?

    WhatsappAccount.where(phone_number_id: phone_number_id).where.not(id: id)
  end

  def shared_number?
    linked_accounts.exists?
  end

  # A shop can connect multiple numbers; exactly one is the default. These
  # callbacks keep that invariant: setting one default unsets the others, and
  # a shop always ends up with a default as long as it has any account.
  before_save :unset_sibling_defaults, if: :should_reassign_default?
  after_create :ensure_shop_has_default
  after_destroy :promote_new_default

  scope :active, -> { where(status: %i[pending_verification verified]) }
  scope :default, -> { where(is_default: true) }

  # Meta's messaging_limit_tier values. Since late 2025 Meta sets the limit per
  # business portfolio, so the phone-level tier is advisory.
  MESSAGING_LIMITS = {
    'TIER_50' => 50, 'TIER_250' => 250, 'TIER_1K' => 1000, 'TIER_2K' => 2000,
    'TIER_10K' => 10_000, 'TIER_100K' => 100_000, 'TIER_UNLIMITED' => nil
  }.freeze
  LOW_QUALITY = %w[RED LOW].freeze
  WARNING_QUALITY = %w[YELLOW MEDIUM].freeze

  def graph_client
    @graph_client ||= Meta::GraphClient.new(token: system_user_token)
  end

  def messaging_limit
    MESSAGING_LIMITS[messaging_limit_tier.to_s.upcase]
  end

  def quality_low?
    LOW_QUALITY.include?(quality_rating.to_s.upcase)
  end

  def quality_warning?
    WARNING_QUALITY.include?(quality_rating.to_s.upcase)
  end

  def record_quality!(rating, limit_tier: nil, at: Time.current)
    attrs = { quality_updated_at: at }
    if rating.present? && rating.to_s.upcase != quality_rating.to_s.upcase
      attrs[:previous_quality_rating] = quality_rating
      attrs[:quality_rating] = rating
    end
    attrs[:messaging_limit_tier] = limit_tier if limit_tier.present?
    update_columns(attrs.merge(updated_at: at))
  end

  def ready_to_send?
    verified? && phone_number_id.present? && registered?
  end

  # Meta rejects every /messages call with `#133010 Account not registered`
  # until POST /{phone_number_id}/register has succeeded, no matter how
  # verified the number looks. Optimistic by design: an account we've never
  # checked is allowed to send, so this gate ships without a backfill silently
  # switching off numbers that are already registered. A 133010 at send time or
  # a status sync flips it to a hard no, and the caller falls back.
  def registered?
    registration_state != UNREGISTERED
  end

  def needs_registration?
    registered_at.blank?
  end

  def registration_state
    metadata['registration_state'].presence || (registered_at.present? ? REGISTERED : nil)
  end

  def registration_error
    metadata['registration_error'].presence
  end

  def mark_registered!(pin: nil)
    self.registration_pin = pin if pin.present?
    update!(
      status: :verified,
      registered_at: registered_at || Time.current,
      metadata: metadata.merge(
        'registration_state' => REGISTERED,
        'registration_checked_at' => Time.current,
        'registration_error' => nil
      )
    )
  end

  def mark_unregistered!(reason: nil)
    update!(
      registered_at: nil,
      metadata: metadata.merge(
        'registration_state' => UNREGISTERED,
        'registration_checked_at' => Time.current,
        'registration_error' => reason.to_s.presence
      )
    )
  end

  def apply_platform_status!(platform_status)
    value = platform_status.to_s.upcase
    return if value.blank?

    if REGISTERED_PLATFORM_STATUSES.include?(value)
      mark_registered!
    elsif UNREGISTERED_PLATFORM_STATUSES.include?(value)
      mark_unregistered!(reason: "Meta reports phone number status #{value}")
    end
  end

  # Merchant-facing name for pickers; falls back to the number / verified name.
  def display_label
    label.presence || display_phone_number.presence || verified_name.presence || "Number #{id}"
  end

  private

  def phone_number_id_unique_per_owner_type
    return if phone_number_id.blank?

    same_type = WhatsappAccount.where(phone_number_id: phone_number_id).where.not(id: id)
    same_type = shop_id.present? ? same_type.shop_owned : same_type.client_owned
    errors.add(:phone_number_id, 'has already been taken') if same_type.exists?
  end

  def exactly_one_owner
    if shop_id.present? && custom_branded_client_id.present?
      errors.add(:base, 'account cannot belong to both a shop and a custom branded client')
    elsif shop_id.blank? && custom_branded_client_id.blank?
      errors.add(:base, 'account must belong to a shop or a custom branded client')
    end
  end

  # All accounts under the SAME owner. Scoping on both columns is what keeps
  # tenants separate: for a merchant account custom_branded_client_id is NULL
  # (matching only that shop's rows); for a client account shop_id is NULL —
  # without the client_id condition, `where(shop_id: nil)` would match every
  # client's accounts across tenants.
  def sibling_scope
    WhatsappAccount.where(shop_id: shop_id, custom_branded_client_id: custom_branded_client_id)
  end

  def should_reassign_default?
    is_default? && (new_record? || will_save_change_to_is_default?)
  end

  # Only one default per owner. For a new default record, id is nil, so
  # `where.not(id: nil)` correctly clears every existing sibling.
  def unset_sibling_defaults
    sibling_scope.where.not(id: id).update_all(is_default: false)
  end

  # Guarantee the owner has a default after adding an account (e.g. the very
  # first one connected, or one created without the flag while none exists).
  def ensure_shop_has_default
    return if sibling_scope.where(is_default: true).exists?
    update_column(:is_default, true)
  end

  # When the default number is disconnected, promote another (prefer an active
  # one) so transactional sends keep resolving to a valid number.
  def promote_new_default
    return unless is_default?
    replacement = sibling_scope.active.order(:id).first ||
                  sibling_scope.order(:id).first
    replacement&.update_column(:is_default, true)
  end
end

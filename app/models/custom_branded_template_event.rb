# frozen_string_literal: true

class CustomBrandedTemplateEvent < ApplicationRecord
  belongs_to :custom_branded_client
  belongs_to :whatsapp_template

  validates :event_id, presence: true
  validates :whatsapp_template_id, uniqueness: true
  validate :variables_are_well_formed
  validate :template_belongs_to_client

  scope :active, -> { where(active: true) }
  scope :for_event, ->(event_id) { where(event_id: event_id.to_s) }

  def self.active_for(client, event_id)
    where(custom_branded_client_id: client.id).for_event(event_id).active.first
  end

  def activate!
    transaction do
      siblings.active.update_all(active: false, updated_at: Time.current)
      update!(active: true)
    end
  end

  def deactivate!
    update!(active: false)
  end

  def siblings
    self.class.where(custom_branded_client_id: custom_branded_client_id, event_id: event_id).where.not(id: id)
  end

  def variable_keys
    Array(variables).map { |v| v['key'].to_s }
  end

  def button_variable_keys
    (button_variables || {}).values.map(&:to_s)
  end

  def required_variable_keys
    (variable_keys + button_variable_keys).uniq
  end

  def live?
    active && whatsapp_template&.approved? && whatsapp_template.whatsapp_account&.ready_to_send? ? true : false
  end

  private

  def variables_are_well_formed
    unless variables.is_a?(Array) && variables.all? { |v| v.is_a?(Hash) && v['key'].present? }
      errors.add(:variables, 'must be a list of { key, label } objects')
    end
    errors.add(:button_variables, 'must be an object') unless button_variables.is_a?(Hash)
  end

  def template_belongs_to_client
    return if whatsapp_template.nil?
    return if whatsapp_template.whatsapp_account&.custom_branded_client_id == custom_branded_client_id

    errors.add(:whatsapp_template, 'does not belong to this brand')
  end
end

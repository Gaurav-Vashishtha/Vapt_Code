module Whatsapp
  # Resolves a template's url_button config against a runtime payload into
  # the slug that Meta needs as the {{1}} parameter of the URL button.
  #
  # Both modes (`predefined` and `base`) collapse to: full destination URL
  # → Cutt.ly short link → strip "https://cutt.ly/" → return slug. When the
  # primary destination is blank and the config declares a `fallback_variable`,
  # that variable's URL is used instead (e.g. tracking URL → order status URL).
  #
  # Returns nil when:
  #   - the template has no url_button config
  #   - both the primary and fallback destinations are blank
  #   - Cutt.ly returns "false" / blank
  class UrlButtonResolver < ApplicationService
    CUTLY_BASE = 'https://cutt.ly/'.freeze

    def initialize(template:, payload:, tracking: nil)
      @template = template
      @tracking = tracking
      @payload = payload.respond_to?(:to_h) ? payload.to_h.deep_stringify_keys : (payload || {})
    end

    def call
      return nil unless template.url_button_present?

      destination = resolve_destination
      return nil if destination.blank?

      destination = Whatsapp::ClickTracker.wrap(destination, **@tracking) if @tracking

      short = NetworkServices::CutlyLinkService.call(destination).to_s
      return nil if short.blank? || short == 'false'

      short.sub(CUTLY_BASE, '')
    end

    private

    attr_reader :template, :payload

    def resolve_destination
      cfg = template.url_button || {}
      primary = primary_destination(cfg)
      return primary if primary.present?
      fallback_destination(cfg)
    end

    def primary_destination(cfg)
      case cfg['mode']
      when 'predefined'
        var = Whatsapp::EventRegistry.variable(template.event_type_key, cfg['variable'])
        return nil unless var
        dig_path(payload, var[:path])
      when 'base'
        var = Whatsapp::EventRegistry.variable(template.event_type_key, cfg['variable'])
        return nil unless var
        suffix = dig_path(payload, var[:path])
        return nil if suffix.blank?
        "#{cfg['base']}#{suffix}"
      end
    end

    def fallback_destination(cfg)
      key = cfg['fallback_variable']
      return nil if key.blank?
      var = Whatsapp::EventRegistry.variable(template.event_type_key, key)
      return nil unless var
      dig_path(payload, var[:path])
    end

    def dig_path(hash, path)
      return '' if path.blank?
      path.to_s.split('.').reduce(hash) do |acc, key|
        break '' if acc.nil?
        if key == 'first' && acc.is_a?(Array)
          acc.first
        elsif acc.respond_to?(:[])
          acc[key] || acc[key.to_sym]
        else
          break ''
        end
      end.to_s
    end
  end
end

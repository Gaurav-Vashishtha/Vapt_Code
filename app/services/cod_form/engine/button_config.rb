# frozen_string_literal: true

unless defined?(::Rails)
  require_relative "defaults"
end

module CodForm
  module Engine
    # COD button config normaliser (ARCHITECTURE C.1 / E.13, BTN-2..9).
    class ButtonConfig
      PRESETS = %w[A B C].freeze
      COLOR = /\A#[0-9a-fA-F]{6}\z/.freeze
      SHADOWS = %w[none sm md lg].freeze
      ICONS = %w[none cash truck cart bolt].freeze
      ANIMATIONS = %w[none pulse shake].freeze
      POSITIONS = %w[below above custom].freeze
      WIDGET_POSITIONS = %w[above_buttons below_buttons custom].freeze
      MAX_SELECTOR = 200
      MAX_LABEL = 120
      LOCALE = /\A([a-z]{2,3}([-_][A-Za-z0-9]{2,8})*|default)\z/.freeze

      class << self
        # => {"preset"=>"A"|"B"|"C", "config"=>{"button","theme","quantity_widget"}, "errors"=>[{"path","code"}]}
        def normalize(preset:, config:)
          errors = []
          defaults = Defaults.button_config
          raw = config.is_a?(Hash) ? config : {}
          chosen = preset.to_s.upcase
          if chosen.empty? then chosen = Defaults.button_preset
          elsif !PRESETS.include?(chosen)
            errors << issue("preset", "invalid_value")
            chosen = Defaults.button_preset
          end

          button = hash(raw["button"])
          d_button = defaults["button"]
          out_button = {
            "labels" => labels(button["labels"], d_button["labels"], "button.labels", errors, required: true),
            "subtitles" => labels(button["subtitles"], d_button["subtitles"], "button.subtitles", errors),
            "style" => style(hash(button["style"]), d_button["style"], errors),
            "placement" => placement(hash(button["placement"]), errors),
            "sticky" => {
              "enabled" => flag(hash(button["sticky"])["enabled"], true),
              "labels" => labels(hash(button["sticky"])["labels"], d_button["sticky"]["labels"], "button.sticky.labels", errors, required: true)
            },
            "cart" => page_button(hash(button["cart"]), d_button["cart"], "button.cart", errors),
            "drawer" => page_button(hash(button["drawer"]), d_button["drawer"], "button.drawer", errors),
            "quick_buy" => {
              "enabled" => flag(hash(button["quick_buy"])["enabled"], false),
              "selector" => selector(hash(button["quick_buy"])["selector"], "button.quick_buy.selector", errors)
            }
          }

          theme = hash(raw["theme"])
          hide = hash(theme["hide"])
          out_theme = {
            "hide" => %w[add_to_cart buy_now checkout drawer_checkout wallets].each_with_object({}) { |key, map| map[key] = hide[key] == true }
          }
          %w[rename_buy_now rename_add_to_cart rename_checkout rename_drawer_checkout].each do |key|
            out_theme[key] = labels(theme[key], defaults["theme"][key], "theme.#{key}", errors)
          end

          widget = hash(raw["quantity_widget"])
          position = widget["position"].to_s
          out_widget = {
            "enabled" => flag(widget["enabled"], true),
            "position" => WIDGET_POSITIONS.include?(position) ? position : "above_buttons",
            "selector" => selector(widget["selector"], "quantity_widget.selector", errors)
          }

          { "preset" => chosen, "config" => { "button" => out_button, "theme" => out_theme, "quantity_widget" => out_widget },
            "errors" => errors }
        end

        private

        def hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def issue(path, code)
          { "path" => path, "code" => code }
        end

        def flag(value, default)
          value == true || value == false ? value : default
        end

        def labels(raw, default, path, errors, required: false)
          map = raw.is_a?(Hash) ? raw : (raw.nil? ? default : { "default" => raw.to_s })
          out = {}
          map.each do |locale, value|
            next unless locale.to_s.match?(LOCALE)

            text = value.to_s.strip
            if text.length > MAX_LABEL
              errors << issue("#{path}.#{locale}", "too_long")
              text = text[0, MAX_LABEL]
            end
            out[locale.to_s] = text
          end
          if out["default"].nil? || (required && out["default"].empty?)
            errors << issue("#{path}.default", "required") if required && !raw.nil?
            out["default"] = default["default"]
          end
          out
        end

        def style(raw, default, errors)
          out = {}
          %w[bg color border_color].each do |key|
            value = raw[key]
            if value.nil? then out[key] = default[key]
            elsif value.to_s.match?(COLOR) then out[key] = value.to_s.downcase
            else
              errors << issue("button.style.#{key}", "invalid_color")
              out[key] = default[key]
            end
          end
          out["border_width"] = integer(raw["border_width"], default["border_width"], 0, 8)
          out["radius"] = integer(raw["radius"], default["radius"], 0, 40)
          out["shadow"] = enum(raw["shadow"], SHADOWS, default["shadow"], "button.style.shadow", errors)
          out["font_size"] = integer(raw["font_size"], default["font_size"], 10, 28)
          out["bold"] = flag(raw["bold"], default["bold"])
          out["height"] = integer(raw["height"], default["height"], 36, 72)
          out["full_width"] = flag(raw["full_width"], default["full_width"])
          out["icon"] = enum(raw["icon"], ICONS, default["icon"], "button.style.icon", errors)
          out["animation"] = enum(raw["animation"], ANIMATIONS, default["animation"], "button.style.animation", errors)
          out
        end

        def placement(raw, errors)
          position = enum(raw["position"], POSITIONS, "below", "button.placement.position", errors)
          chosen = selector(raw["selector"], "button.placement.selector", errors)
          errors << issue("button.placement.selector", "required") if position == "custom" && chosen.empty?
          { "position" => position, "selector" => chosen }
        end

        def page_button(raw, default, path, errors)
          { "enabled" => flag(raw["enabled"], default["enabled"]),
            "labels" => labels(raw["labels"], default["labels"], "#{path}.labels", errors, required: true),
            "selector" => selector(raw["selector"], "#{path}.selector", errors) }
        end

        def selector(value, path, errors)
          text = value.to_s.strip
          return "" if text.empty?

          if text.length > MAX_SELECTOR || text.match?(/[<>{}]/)
            errors << issue(path, "invalid_selector")
            return ""
          end
          text
        end

        def enum(value, allowed, default, path, errors)
          return default if value.nil?
          return value.to_s if allowed.include?(value.to_s)

          errors << issue(path, "invalid_value")
          default
        end

        def integer(value, default, min, max)
          number = value.is_a?(Numeric) ? value.round : Integer(value.to_s, exception: false)
          number.nil? ? default : [[number, min].max, max].min
        end
      end
    end
  end
end

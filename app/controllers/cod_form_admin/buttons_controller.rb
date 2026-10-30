# frozen_string_literal: true

module CodFormAdmin
  # Buttons screen (D.15): preset + cod_button_configs.config (C.1.2 stored keys).
  class ButtonsController < BaseController
    before_action :load_button

    def show
      render json: button_json
    end

    # PUT /cod_form/button  {"preset", "config"}
    def update
      preset = body.key?("preset") ? body["preset"].to_s : @button.preset
      config = body.key?("config") ? body_hash("config") : @button.config
      invalid!("config", "must be an object") if config.nil?
      gate!("preset_a") if preset == "A" && @button.preset != "A"

      result = CodForm::Engine::ButtonConfig.normalize(preset: preset, config: config)
      errors = engine_errors(result["errors"])
      raise ValidationError.new(errors) if errors.any?

      old = button_json
      @button.update!(preset: result["preset"], config: result["config"])
      if button_json != old
        audit("button.preset", old["preset"], @button.preset)
        audit_changes("button.config", old["config"], @button.config)
        bump!
      end
      stamp_setup_state("preset_chosen_at")
      render json: button_json
    end

    private

    def load_button
      @button = CodForm::ButtonConfig.for(@shop)
    end

    def button_json
      { "preset" => @button.preset, "config" => @button.config }
    end
  end
end

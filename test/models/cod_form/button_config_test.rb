# frozen_string_literal: true

require "test_helper"

class CodForm::ButtonConfigTest < ActiveSupport::TestCase
  test "for creates the shop's row with preset B and the default config" do
    shop = shops(:regular_shop)
    button = CodForm::ButtonConfig.for(shop)

    assert_equal "B", button.preset
    assert_equal CodForm::Engine::Defaults.button_config, button.config
    assert_equal button.id, CodForm::ButtonConfig.for(shop).id
  end

  test "preset must be A, B or C" do
    button = CodForm::ButtonConfig.new(shop: shops(:regular_shop), preset: "D")
    assert_not button.valid?
  end
end

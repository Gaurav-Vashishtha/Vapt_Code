# frozen_string_literal: true

class AddEnterprisePlusPlan < ActiveRecord::Migration[7.2]
  def up
    return if Plan.exists?(name: "Enterprise Plus")

    Plan.create!(name: "Enterprise Plus", price: "59")
  end

  def down
    Plan.find_by(name: "Enterprise Plus")&.destroy
  end
end

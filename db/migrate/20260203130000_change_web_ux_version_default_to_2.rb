# frozen_string_literal: true

class ChangeWebUxVersionDefaultTo2 < ActiveRecord::Migration[7.0]
  def up
    change_column_default :settings, :web_ux_version, from: 1, to: 2
  end

  def down
    change_column_default :settings, :web_ux_version, from: 2, to: 1
  end
end

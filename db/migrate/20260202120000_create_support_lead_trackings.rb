# frozen_string_literal: true

class CreateSupportLeadTrackings < ActiveRecord::Migration[7.2]
  def change
    create_table :support_lead_trackings do |t|
      t.references :shop, null: false, foreign_key: true, index: { unique: true }
      t.string :assigned_engineer
      t.boolean :activated, null: false, default: false
      t.boolean :verified_setup, null: false, default: false
      t.boolean :contacted, null: false, default: false
      t.boolean :reminder_1_sent, null: false, default: false
      t.boolean :reminder_2_sent, null: false, default: false
      t.boolean :reminder_3_sent, null: false, default: false
      t.boolean :not_interested, null: false, default: false
      t.boolean :onboarded_to_free_plan, null: false, default: false
      t.boolean :onboarded_to_paid_plan, null: false, default: false
      t.timestamps
    end
  end
end

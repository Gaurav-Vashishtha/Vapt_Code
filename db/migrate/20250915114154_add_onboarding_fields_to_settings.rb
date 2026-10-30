class AddOnboardingFieldsToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :quick_onboarding_visited, :boolean
    add_column :settings, :user_journey, :string
  end
end

class CreateFollowUpComments < ActiveRecord::Migration[7.2]
  def change
    create_table :follow_up_comments do |t|
      t.references :follow_up, null: false, foreign_key: true
      t.text :comment, null: false
      t.string :commented_by

      t.timestamps
    end
  end
end

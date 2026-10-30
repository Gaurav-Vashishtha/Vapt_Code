class CreateUnsubscribedEmails < ActiveRecord::Migration[7.2]
  def change
    create_table :unsubscribed_emails do |t|
      t.string :email
      t.string :source
      t.datetime :unsubscribed_at

      t.timestamps
    end
  end
end

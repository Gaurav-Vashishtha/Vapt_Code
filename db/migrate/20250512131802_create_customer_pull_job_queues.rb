class CreateCustomerPullJobQueues < ActiveRecord::Migration[6.0]
  def change
    create_table :customer_pull_job_queues do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :status, null: false, default: 'pending' # pending, processing, done, failed
      t.timestamps
    end
    add_index :customer_pull_job_queues, :status
  end
end

class AddErrorMessageToCustomerPullJobQueues < ActiveRecord::Migration[7.2]
  def change
    add_column :customer_pull_job_queues, :error_message, :text
  end
end

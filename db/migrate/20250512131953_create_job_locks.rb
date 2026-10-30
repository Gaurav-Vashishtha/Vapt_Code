class CreateJobLocks < ActiveRecord::Migration[6.0]
  def change
    create_table :job_locks do |t|
      t.string :job_name, null: false
      t.datetime :locked_at, null: false
      t.timestamps
    end
    add_index :job_locks, :job_name, unique: true
  end
end

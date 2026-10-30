class CreatePlansData < ActiveRecord::Migration[6.0]

  def self.up
    Plan.create({ name: 'Free', price: 0})
    Plan.create({ name: 'Pro', price: 5})
  end

  def self.down
    Plan.delete_all
  end
end

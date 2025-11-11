class AddCostCentsToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :cost_cents, :integer, default: 0, null: false
    add_index  :products, :cost_cents
  end
end

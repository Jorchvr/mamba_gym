class AddNameToStoreSaleItems < ActiveRecord::Migration[8.0]
  def change
    add_column :store_sale_items, :name, :string
  end
end

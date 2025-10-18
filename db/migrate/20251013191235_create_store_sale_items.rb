class CreateStoreSaleItems < ActiveRecord::Migration[7.1]
  def change
    create_table :store_sale_items do |t|
      t.references :store_sale, null: false, foreign_key: true
      t.references :product,    null: false, foreign_key: true
      t.integer :quantity,          null: false
      t.integer :unit_price_cents,  null: false

      t.timestamps
    end
  end
end

class CreateStoreSales < ActiveRecord::Migration[7.1]
  def change
    create_table :store_sales do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :payment_method, null: false, default: 0  # enum: 0 cash, 1 transfer
      t.integer :total_cents,    null: false, default: 0
      t.datetime :occurred_at,   null: false

      t.timestamps
    end

    add_index :store_sales, :occurred_at
  end
end

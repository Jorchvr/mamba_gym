class CreateSales < ActiveRecord::Migration[8.0]
  def change
    create_table :sales do |t|
      t.references :client, null: false, foreign_key: true
      t.references :user,   null: false, foreign_key: true
      t.integer :membership_type, null: false
      t.integer :amount_cents,    null: false
      t.integer :payment_method,  null: false
      t.datetime :occurred_at,    null: false

      t.timestamps
    end

    add_index :sales, :occurred_at
  end
end

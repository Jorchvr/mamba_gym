class CreateInventoryEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :inventory_events do |t|
      t.references :product, null: false, foreign_key: true
      t.references :user,    null: false, foreign_key: true
      t.integer :kind,       null: false, default: 0 # 0=in, 1=out, 2=adjust
      t.integer :quantity,   null: false
      t.datetime :happened_at
      t.string :note

      t.timestamps
    end

    add_index :inventory_events, :happened_at
  end
end

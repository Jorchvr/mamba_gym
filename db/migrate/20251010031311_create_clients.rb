class CreateClients < ActiveRecord::Migration[7.1]
  def change
    create_table :clients do |t|
      t.string  :name, null: false
      t.integer :age
      t.decimal :weight, precision: 5, scale: 2
      t.decimal :height, precision: 4, scale: 2
      t.integer :membership_type, null: false, default: 0
      t.date    :enrolled_on
      t.date    :next_payment_on
      t.references :user, foreign_key: true

      t.timestamps
    end

    add_index :clients, :membership_type
  end
end

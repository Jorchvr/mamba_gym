class ChangeClientsHeightPrecision < ActiveRecord::Migration[8.0]
  def change
    change_column :clients, :height, :decimal, precision: 5, scale: 2
  end
end

class MakeSalesClientNullable < ActiveRecord::Migration[7.1]
  def change
    # Permite null en client_id para ventas sin cliente (mini-tienda de Griselle)
    change_column_null :sales, :client_id, true
  end
end

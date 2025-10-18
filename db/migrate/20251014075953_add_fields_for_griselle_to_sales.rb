class AddFieldsForGriselleToSales < ActiveRecord::Migration[7.1]
  def change
    # Monto en centavos
    add_column :sales, :total_cents, :integer, null: false, default: 0 unless column_exists?(:sales, :total_cents)

    # Método de pago (cash | transfer)
    add_column :sales, :payment_method, :string, null: false, default: "cash" unless column_exists?(:sales, :payment_method)

    # Relación con usuario que cobra (opcional si ya existe)
    add_reference :sales, :user, foreign_key: true unless column_exists?(:sales, :user_id)

    # Detalle de líneas del carrito (json); si tu BD es Postgres puedes usar :jsonb
    add_column :sales, :metadata, :json, default: {} unless column_exists?(:sales, :metadata)
  end
end

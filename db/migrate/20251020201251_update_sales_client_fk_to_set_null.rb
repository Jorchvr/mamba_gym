class UpdateSalesClientFkToSetNull < ActiveRecord::Migration[7.1]
  def up
    # Quita la FK actual (nombre genérico de Rails)
    remove_foreign_key :sales, :clients

    # Crea la FK con ON DELETE SET NULL
    add_foreign_key :sales, :clients, column: :client_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :sales, :clients
    add_foreign_key :sales, :clients, column: :client_id
  end
end

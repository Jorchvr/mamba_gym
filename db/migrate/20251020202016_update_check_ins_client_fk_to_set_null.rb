class UpdateCheckInsClientFkToSetNull < ActiveRecord::Migration[7.1]
  def up
    # Quita la FK actual (nombre tipo fk_rails_xxx)
    remove_foreign_key :check_ins, :clients

    # Crea la FK con ON DELETE SET NULL
    add_foreign_key :check_ins, :clients, column: :client_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :check_ins, :clients
    add_foreign_key :check_ins, :clients, column: :client_id
  end
end

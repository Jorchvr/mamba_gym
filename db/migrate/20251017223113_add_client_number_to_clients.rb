# db/migrate/20251018_add_client_number_to_clients.rb
class AddClientNumberToClients < ActiveRecord::Migration[7.1]
  def change
    add_column :clients, :client_number, :integer
    add_index  :clients, :client_number, unique: true

    # Backfill simple: si no hay client_number, lo igualamos al id para no romper listados
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE clients
          SET client_number = id
          WHERE client_number IS NULL;
        SQL
      end
    end
  end
end

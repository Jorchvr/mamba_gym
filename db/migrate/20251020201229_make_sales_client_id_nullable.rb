class MakeSalesClientIdNullable < ActiveRecord::Migration[7.1]
  def change
    change_column_null :sales, :client_id, true
  end
end

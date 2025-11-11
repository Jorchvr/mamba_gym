class MakeCheckInsClientIdNullable < ActiveRecord::Migration[7.1]
  def change
    change_column_null :check_ins, :client_id, true
  end
end

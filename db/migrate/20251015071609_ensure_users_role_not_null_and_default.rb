class EnsureUsersRoleNotNullAndDefault < ActiveRecord::Migration[7.2]
  def up
    # Si la columna role existe, asegúrate del default y del NOT NULL
    return unless column_exists?(:users, :role)

    # 1) Default = 0
    change_column_default :users, :role, from: nil, to: 0

    # 2) Backfill para filas que ya estén en NULL
    execute <<~SQL.squish
      UPDATE users SET role = 0 WHERE role IS NULL;
    SQL

    # 3) NOT NULL
    change_column_null :users, :role, false
  end

  def down
    return unless column_exists?(:users, :role)
    change_column_null :users, :role, true
    change_column_default :users, :role, from: 0, to: nil
  end
end

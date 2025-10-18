class AddSuperuserToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :superuser, :boolean, default: false, null: false
    add_index  :users, :superuser
  end
end

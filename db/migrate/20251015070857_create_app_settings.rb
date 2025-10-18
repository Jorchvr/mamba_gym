class CreateAppSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :app_settings do |t|
      t.string :key
      t.text :value

      t.timestamps
    end
  end
end

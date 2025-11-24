class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.boolean :admin, default: true, null: false

      t.timestamps
    end
  end
end

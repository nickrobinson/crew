class CreateRepositories < ActiveRecord::Migration[8.1]
  def change
    create_table :repositories do |t|
      t.string :github_url, null: false
      t.string :name, null: false
      t.text :description
      t.string :primary_language
      t.integer :stars_count, default: 0
      t.string :import_status, default: "pending"
      t.datetime :imported_at

      t.timestamps
    end
    add_index :repositories, :github_url, unique: true
  end
end

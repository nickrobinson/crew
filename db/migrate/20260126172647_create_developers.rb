class CreateDevelopers < ActiveRecord::Migration[8.1]
  def change
    create_table :developers do |t|
      t.string :github_username, null: false
      t.integer :github_id, null: false
      t.string :avatar_url
      t.string :profile_url
      t.string :name
      t.text :bio
      t.string :location
      t.string :company
      t.string :email
      t.integer :followers_count, default: 0
      t.integer :public_repos_count, default: 0
      t.json :top_languages, default: []
      t.string :status, default: "new"
      t.text :notes

      t.timestamps
    end
    add_index :developers, :github_username, unique: true
    add_index :developers, :github_id, unique: true
  end
end

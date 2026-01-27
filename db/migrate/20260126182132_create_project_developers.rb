class CreateProjectDevelopers < ActiveRecord::Migration[8.1]
  def change
    create_table :project_developers do |t|
      t.references :project, null: false, foreign_key: true
      t.references :developer, null: false, foreign_key: true
      t.string :status, default: "new", null: false
      t.text :notes

      t.timestamps
    end

    add_index :project_developers, [:project_id, :developer_id], unique: true
  end
end

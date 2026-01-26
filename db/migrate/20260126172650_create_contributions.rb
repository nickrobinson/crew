class CreateContributions < ActiveRecord::Migration[8.1]
  def change
    create_table :contributions do |t|
      t.references :developer, null: false, foreign_key: true
      t.references :repository, null: false, foreign_key: true
      t.integer :contributions_count, default: 0

      t.timestamps
    end
    add_index :contributions, [:developer_id, :repository_id], unique: true
  end
end

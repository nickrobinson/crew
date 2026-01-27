class AddProjectToRepositories < ActiveRecord::Migration[8.1]
  def change
    add_reference :repositories, :project, null: true, foreign_key: true
  end
end

class MigrateExistingDataToProjects < ActiveRecord::Migration[8.1]
  def up
    # Create default project for existing data
    default_project_id = execute(<<~SQL).first&.dig("id")
      INSERT INTO projects (name, description, created_at, updated_at)
      VALUES ('Default Project', 'Migrated from existing data', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING id
    SQL

    return unless default_project_id

    # Assign all existing repositories to the default project
    execute(<<~SQL)
      UPDATE repositories SET project_id = #{default_project_id} WHERE project_id IS NULL
    SQL

    # Migrate developer statuses to project_developers
    execute(<<~SQL)
      INSERT INTO project_developers (project_id, developer_id, status, notes, created_at, updated_at)
      SELECT #{default_project_id}, id, COALESCE(status, 'new'), notes, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM developers
    SQL
  end

  def down
    # Remove all project_developers records
    execute("DELETE FROM project_developers")

    # Remove project_id from repositories
    execute("UPDATE repositories SET project_id = NULL")

    # Delete the default project
    execute("DELETE FROM projects WHERE name = 'Default Project'")
  end
end

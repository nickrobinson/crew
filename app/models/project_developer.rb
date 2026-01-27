class ProjectDeveloper < ApplicationRecord
  belongs_to :project
  belongs_to :developer

  STATUSES = %w[new interesting contacted not_a_fit].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :developer_id, uniqueness: { scope: :project_id }

  scope :by_status, ->(status) { where(status: status) if status.present? }

  def status_label
    status.titleize.gsub("_", " ")
  end
end

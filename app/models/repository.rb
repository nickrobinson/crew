class Repository < ApplicationRecord
  belongs_to :project
  has_many :contributions, dependent: :destroy
  has_many :developers, through: :contributions

  validates :github_url, presence: true, uniqueness: true
  validates :name, presence: true
  validates :project, presence: true

  IMPORT_STATUSES = %w[pending importing imported failed].freeze
  validates :import_status, inclusion: { in: IMPORT_STATUSES }

  scope :imported, -> { where(import_status: "imported") }
  scope :importing, -> { where(import_status: "importing") }

  def owner
    name.split("/").first
  end

  def repo_name
    name.split("/").last
  end
end

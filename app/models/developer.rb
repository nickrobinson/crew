class Developer < ApplicationRecord
  has_many :contributions, dependent: :destroy
  has_many :repositories, through: :contributions

  validates :github_username, presence: true, uniqueness: true
  validates :github_id, presence: true, uniqueness: true

  STATUSES = %w[new interesting contacted not_a_fit].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :by_location, ->(loc) { where("location LIKE ?", "%#{loc}%") if loc.present? }
  scope :with_email, -> { where.not(email: [nil, ""]) }

  def total_contributions
    contributions.sum(:contributions_count)
  end

  def status_label
    status.titleize.gsub("_", " ")
  end
end

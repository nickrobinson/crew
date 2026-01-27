class Developer < ApplicationRecord
  has_many :contributions, dependent: :destroy
  has_many :repositories, through: :contributions
  has_many :project_developers, dependent: :destroy
  has_many :projects, through: :project_developers

  validates :github_username, presence: true, uniqueness: true
  validates :github_id, presence: true, uniqueness: true

  scope :by_location, ->(loc) { where("location LIKE ?", "%#{loc}%") if loc.present? }
  scope :with_email, -> { where.not(email: [nil, ""]) }

  def total_contributions
    contributions.sum(:contributions_count)
  end
end


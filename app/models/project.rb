class Project < ApplicationRecord
  has_many :repositories, dependent: :destroy
  has_many :project_developers, dependent: :destroy
  has_many :developers, through: :project_developers

  validates :name, presence: true

  def developers_count
    project_developers.count
  end

  def repositories_count
    repositories.count
  end
end

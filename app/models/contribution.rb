class Contribution < ApplicationRecord
  belongs_to :developer
  belongs_to :repository

  validates :developer_id, uniqueness: { scope: :repository_id }
end

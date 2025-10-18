class CheckIn < ApplicationRecord
  belongs_to :client
  belongs_to :user

  validates :occurred_at, presence: true
end

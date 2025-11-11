class CheckIn < ApplicationRecord
  belongs_to :client
  belongs_to :user

  validates :occurred_at, presence: true

  before_validation :ensure_occurred_at

  scope :today, -> { where(occurred_at: Time.zone.today.all_day) }

  private

  def ensure_occurred_at
    self.occurred_at ||= Time.current
  end
end

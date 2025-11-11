# app/models/store_sale.rb
class StoreSale < ApplicationRecord
  belongs_to :user
  has_many :store_sale_items, dependent: :destroy

  enum :payment_method, { cash: 0, transfer: 1 }

  validates :total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :user, presence: true

  # Igual que en Sale: si no viene occurred_at, lo seteamos
  before_validation :ensure_occurred_at

  scope :on_date, ->(date) {
    from = date.beginning_of_day
    to   = date.end_of_day
    where("COALESCE(occurred_at, created_at) BETWEEN ? AND ?", from, to)
  }

  def total
    (total_cents.to_i / 100.0).round(2)
  end

  private

  def ensure_occurred_at
    self.occurred_at ||= Time.current
  end
end

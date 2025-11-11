class InventoryEvent < ApplicationRecord
  belongs_to :product
  belongs_to :user

  enum :kind, { in: 0, out: 1, adjust: 2 } # por ahora usamos :in para reabastecer
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :happened_at, presence: true

  before_validation :ensure_happened_at

  private

  def ensure_happened_at
    self.happened_at ||= Time.current
  end
end

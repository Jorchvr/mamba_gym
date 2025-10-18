class StoreSale < ApplicationRecord
  belongs_to :user
  has_many :store_sale_items, dependent: :destroy

  # ✅ Usa 2 argumentos POSICIONALES (firma 1..2): nombre + hash de valores
  enum :payment_method, { cash: 0, transfer: 1 }

  validates :payment_method, presence: true
  validates :total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :occurred_at, presence: true
end

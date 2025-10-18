class Sale < ApplicationRecord
  # En ventas de clases (Griselle) puede no haber cliente
  belongs_to :client, optional: true
  belongs_to :user

  # Enums con sintaxis nueva + prefijos
  enum :membership_type, { day: 0, week: 1, month: 2 }, prefix: :membership
  enum :payment_method,  { cash: 0, transfer: 1 },       prefix: :paid

  # Validaciones
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :occurred_at, presence: true
  validates :payment_method, presence: true
  validates :user, presence: true

  scope :today, -> { where(occurred_at: Time.zone.today.all_day) }

  def amount
    amount_cents.to_i / 100.0
  end
end

# app/models/client.rb
class Client < ApplicationRecord
  belongs_to :user, optional: true
  has_one_attached :photo

  enum :membership_type, { day: 0, week: 1, month: 2 }

  validates :name, presence: true, length: { maximum: 120 }
  validates :age, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :weight, numericality: { greater_than: 0 }, allow_nil: true
  validates :height, numericality: { greater_than: 0 }, allow_nil: true
  validates :membership_type, presence: true

  # Nuevo: número de cliente sugerido y único
  validates :client_number, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :client_number, uniqueness: true, allow_nil: true

  before_validation :normalize_measures
  before_validation :ensure_client_number

  PRICES = {
    "day"   => 30_00,
    "week"  => 70_00,
    "month" => 200_00
  }.freeze

  def price_cents
    PRICES[membership_type]
  end

  def set_enrollment_dates!(from: Date.current)
    self.enrolled_on ||= from
    self.next_payment_on =
      case membership_type
      when "day"   then from + 1.day
      when "week"  then from + 1.week
      when "month" then from + 1.month
      else              from
      end
  end

  private

  # Permite height 1.69 (m) o 169 (cm)
  def normalize_measures
    if height.present?
      h = height.to_f
      h = h / 100.0 if h >= 3.0
      self.height = h.round(2)
    end
  end

  # Si no se envió client_number, sugerimos el siguiente consecutivo
  def ensure_client_number
    return if client_number.present?

    # buscamos el máximo existente (en client_number si hay, si no, caemos a id)
    max_existing =
      self.class.maximum(:client_number) ||
      self.class.maximum(:id) ||
      0

    self.client_number = max_existing + 1
  end
end

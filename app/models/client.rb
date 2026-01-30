class Client < ApplicationRecord
  belongs_to :user, optional: true
  has_one_attached :photo

  # Permite recibir la foto de la cámara
  attr_accessor :photo_base64

  has_many :sales,     dependent: :nullify
  has_many :check_ins, dependent: :nullify

  # === 🟢 IMPORTANTE: La lista debe coincidir con la de Sale ===
  enum :membership_type, {
    day: 0,
    week: 1,
    month: 2,
    couple: 3,
    semester: 4,
    visit: 5,
    promo: 6
  }

  # ================== HUELLA DIGITAL ==================
  scope :with_fingerprint, -> { where.not(fingerprint: [ nil, "" ]) }

  validates :name, presence: true, length: { maximum: 120 }
  validates :age, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :membership_type, presence: true
  validates :client_number, uniqueness: true, allow_nil: true

  before_validation :ensure_client_number
  before_validation :normalize_measures

  # PRECIOS (En centavos)
  PRICES = {
    "visit"      => 100_00,
    "week"       => 200_00,
    "month"      => 550_00,
    "couple"     => 950_00,
    "semester"   => 2300_00,
    "promo_open" => 100_00,
    "promo_feb"  => 250_00
  }.freeze

  def price_cents
    PRICES[membership_type.to_s] || 0
  end

  def set_enrollment_dates!(from: Date.current)
    self.enrolled_on ||= from
    self.next_payment_on = case membership_type
    when "visit", "day" then from + 1.day
    when "week"         then from + 1.week
    when "semester"     then from + 6.months
    else                     from + 1.month # Mes, Pareja, Promos
    end
  end

  private

  def normalize_measures
    if height.present? && height >= 3.0
      self.height = (height.to_f / 100.0).round(2)
    end
  end

  def ensure_client_number
    return if client_number.present?
    max = self.class.maximum(:client_number) || self.class.maximum(:id) || 0
    self.client_number = max + 1
  end
end

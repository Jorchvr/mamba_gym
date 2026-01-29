class Client < ApplicationRecord
  belongs_to :user, optional: true
  has_one_attached :photo

  # === 🔥 AGREGADO: Esto permite recibir la foto de la cámara sin errores ===
  attr_accessor :photo_base64

  # Ventas quedan con client_id = NULL si se borra el cliente
  has_many :sales,     dependent: :nullify
  # Check-ins quedan con client_id = NULL si se borra el cliente
  has_many :check_ins, dependent: :nullify

  # === 🟢 ACTUALIZADO: Nuevos tipos de membresía ===
  # Se agregan couple (pareja), semester (semestre) y visit (visita)
  enum :membership_type, { day: 0, week: 1, month: 2, couple: 3, semester: 4, visit: 5 }

  # ================== HUELLA DIGITAL ==================
  scope :with_fingerprint, -> { where.not(fingerprint: [ nil, "" ]) }
  # ====================================================

  validates :name, presence: true, length: { maximum: 120 }
  validates :age, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :weight, numericality: { greater_than: 0 }, allow_nil: true
  validates :height, numericality: { greater_than: 0 }, allow_nil: true
  validates :membership_type, presence: true

  # Número de cliente sugerido y único
  validates :client_number, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :client_number, uniqueness: true, allow_nil: true

  before_validation :normalize_measures
  before_validation :ensure_client_number

  # ===== 🟢 ACTUALIZADO: PRECIOS EN CENTAVOS =====
  # Mes: $550 | Pareja: $950 | Semana: $200 | Visita: $100 | Semestre: $2300
  # Promos: Apertura $100 | Febrero $250
  PRICES = {
    "visit"    => 100_00,  # Visita 1 día ($100)
    "day"      => 100_00,  # Alias para sistema anterior ($100)
    "week"     => 200_00,  # Semana ($200)
    "month"    => 550_00,  # Mes ($550)
    "couple"   => 950_00,  # Pareja ($950)
    "semester" => 2300_00, # Semestre ($2300)
    # Promociones (Si se seleccionan en el form)
    "promo_open" => 100_00, # Apertura ($100)
    "promo_feb"  => 250_00  # Febrero ($250)
  }.freeze

  def price_cents
    PRICES[membership_type.to_s] || 0
  end

  def set_enrollment_dates!(from: Date.current)
    self.enrolled_on ||= from

    # === 🟢 ACTUALIZADO: Cálculo de fechas según nuevos planes ===
    self.next_payment_on =
      case membership_type
      when "visit", "day" then from + 1.day
      when "week"         then from + 1.week
      when "month", "couple", "promo_feb", "promo_open" then from + 1.month
      when "semester"     then from + 6.months
      else                     from + 1.month
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

    max_existing =
      self.class.maximum(:client_number) ||
      self.class.maximum(:id) ||
      0

    self.client_number = max_existing + 1
  end
end

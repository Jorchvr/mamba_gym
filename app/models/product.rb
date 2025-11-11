class Product < ApplicationRecord
  # ===== Campos virtuales en MXN (pesos) =====
  attr_accessor :price_mxn, :cost_mxn

  # ===== Validaciones =====
  validates :name, presence: true
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :cost_cents,  numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :stock,       numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # ===== Normalización de dinero (de MXN a centavos) =====
  before_validation :apply_money_virtuals

  # ===== Métodos de ayuda =====
  def price
    (price_cents.to_i / 100.0).round(2)
  end

  def cost
    (cost_cents.to_i / 100.0).round(2)
  end

  def profit_cents
    price_cents.to_i - cost_cents.to_i
  end

  def profit
    (profit_cents / 100.0).round(2)
  end

  def margin_percentage
    return 0.0 if price_cents.to_i <= 0
    ((profit_cents.to_f / price_cents.to_f) * 100.0).round(2)
  end

  # Para que el form muestre valores en MXN aunque no hayas seteado los virtuales
  def price_mxn
    @price_mxn.presence || (price_cents ? (price_cents.to_f / 100.0) : nil)
  end

  def cost_mxn
    @cost_mxn.presence || (cost_cents ? (cost_cents.to_f / 100.0) : nil)
  end

  private

  def apply_money_virtuals
    # Si llegan price_mxn / cost_mxn desde el formulario, conviértelos
    if @price_mxn.present?
      self.price_cents = to_cents(@price_mxn)
    end

    if @cost_mxn.present?
      self.cost_cents = to_cents(@cost_mxn)
    end

    # Defaults seguros para evitar nils
    self.price_cents ||= 0
    self.cost_cents  ||= 0
  end

  def to_cents(value)
    # Acepta números o strings con coma/punto
    v = value.is_a?(String) ? value.tr(",", ".").to_f : value.to_f
    (v * 100).round
  end
end

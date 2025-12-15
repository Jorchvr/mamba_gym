class StoreSaleItem < ApplicationRecord
  belongs_to :store_sale
  belongs_to :product

  # Validaciones básicas de números
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # ✅ VALIDACIÓN CLAVE: Revisa el stock antes de crear
  validate :check_stock_availability, on: :create

  private

  def check_stock_availability
    # Si no hay producto asociado, salimos
    return unless product.present?

    # Si intentas vender más de lo que hay en inventario
    if product.stock < quantity
      # Agregamos el error. Esto hace que 'save!' falle y el controlador muestre la alerta roja.
      errors.add(:base, "Stock insuficiente para '#{product.name}'. Disponible: #{product.stock}, Solicitado: #{quantity}.")
    end
  end
end

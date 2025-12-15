class StoreSaleItem < ApplicationRecord
  belongs_to :store_sale
  belongs_to :product

  # Validaciones existentes (las conservamos)
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # --- NUEVA VALIDACIÓN: Verificar stock antes de crear ---
  validate :check_stock_availability, on: :create

  private

  def check_stock_availability
    # Si no hay producto asociado, no hacemos nada (Rails fallará por falta de asociación si es obligatorio)
    return unless product.present?

    # Verificamos si la cantidad que intentas vender es mayor al stock que tiene el producto
    if product.stock < quantity
      # Agregamos un error al modelo.
      # Esto hace que 'save!' se detenga y envíe este mensaje al controlador.
      errors.add(:base, "Stock insuficiente para '#{product.name}'. Disponible: #{product.stock}, Solicitado: #{quantity}.")
    end
  end
end

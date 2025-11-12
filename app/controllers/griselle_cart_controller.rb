# app/controllers/griselle_cart_controller.rb
class GriselleCartController < ApplicationController
  before_action :authenticate_user!

  def show
    @cart = session[:griselle_cart].is_a?(Array) ? session[:griselle_cart] : []
  end

  def add
    # Solo aceptamos "custom"
    unless params[:id] == "custom"
      redirect_to griselle_cart_path, alert: "Solo se permite precio personalizado."
      return
    end

    desc   = params[:description].to_s.strip
    amount = params[:amount].to_s.strip

    if desc.blank? || amount.blank? || amount.to_f <= 0
      redirect_to griselle_cart_path, alert: "Descripción y monto válido son requeridos."
      return
    end

    price_cents = (amount.to_f * 100).round
    session[:griselle_cart] ||= []
    session[:griselle_cart] << {
      id: SecureRandom.uuid,
      name: desc,
      qty: 1,
      price_cents: price_cents
    }

    redirect_to griselle_cart_path, notice: "Agregado: #{desc} ($#{amount})"
  end

  def increment
    line_id = params[:line_id].to_s
    mutate_line(line_id) { |l| l[:qty] = l[:qty].to_i + 1 }
  end

  def decrement
    line_id = params[:line_id].to_s
    mutate_line(line_id) do |l|
      new_qty = l[:qty].to_i - 1
      if new_qty > 0
        l[:qty] = new_qty
      else
        :remove
      end
    end
  end

  def remove
    line_id = params[:line_id].to_s
    session[:griselle_cart] ||= []
    session[:griselle_cart].reject! { |l| l[:id].to_s == line_id }
    redirect_to griselle_cart_path
  end

  def checkout
    pm = %w[cash transfer].include?(params[:payment_method]) ? params[:payment_method] : "cash"
    cart = session[:griselle_cart].is_a?(Array) ? session[:griselle_cart] : []
    if cart.blank?
      redirect_to griselle_cart_path, alert: "No hay items en el carrito."
      return
    end

    # 1) Buscar/crear el producto genérico de servicio para griselle
    service = Product.find_by(sku: "GRISELLE") ||
              Product.create!(
                sku: "GRISELLE",
                name: "Servicio Griselle",
                price_cents: 0,
                stock: 0
              )

    # 2) Calcular total y crear venta
    total_cents = cart.sum { |l| l[:price_cents].to_i * l[:qty].to_i }

    sale = StoreSale.create!(
      user: current_user,
      payment_method: pm,   # enum existente
      total_cents: total_cents,
      occurred_at: Time.current
      # Si tu modelo tiene :note o :source, podrías dejar constancia:
      # note: "GRISELLE",
      # source: "griselle"
    )

    # 3) Crear items (precio por línea = monto personalizado)
    cart.each do |l|
      qty  = l[:qty].to_i
      unit = l[:price_cents].to_i
      next if qty <= 0 || unit <= 0

      sale.store_sale_items.create!(
        product_id: service.id,
        quantity: qty,
        unit_price_cents: unit
        # Si StoreSaleItem tiene :note o :description, puedes guardar el texto:
        # note: l[:name]
      )
    end

    # 4) Limpiar carrito
    session[:griselle_cart] = []

    redirect_to griselle_cart_path, notice: "Venta registrada en POS (#{pm})."
  rescue => e
    redirect_to griselle_cart_path, alert: "No se pudo realizar el cobro: #{e.message}"
  end

  private

  def mutate_line(line_id)
    session[:griselle_cart] ||= []
    cart = session[:griselle_cart]
    i = cart.index { |l| l[:id].to_s == line_id }
    if i.nil?
      redirect_to griselle_cart_path and return
    end

    result = yield(cart[i])
    if result == :remove
      cart.delete_at(i)
    end

    redirect_to griselle_cart_path
  end
end

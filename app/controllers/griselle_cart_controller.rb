# app/controllers/griselle_cart_controller.rb
class GriselleCartController < ApplicationController
  before_action :authenticate_user!

  def show
    @cart = session[:griselle_cart].is_a?(Array) ? session[:griselle_cart] : []
  end

  # POST /griselle_cart/add  (solo custom)
  def add
    session[:griselle_cart] ||= []
    cart = session[:griselle_cart].is_a?(Array) ? session[:griselle_cart] : []

    if params[:id] == "custom"
      desc = params[:description].to_s.strip
      amount = params[:amount].to_s
      amount_cents = (BigDecimal(amount) * 100).to_i rescue 0
      if amount_cents <= 0
        redirect_to griselle_cart_path, alert: "Monto inválido"; return
      end

      line = {
        id: SecureRandom.hex(6),
        name: (desc.presence || "Servicio"),
        price_cents: amount_cents,
        qty: 1
      }
      cart << line
      session[:griselle_cart] = cart
      redirect_to griselle_cart_path, notice: "Agregado"
    else
      redirect_to griselle_cart_path, alert: "Solo se permite precio personalizado"
    end
  end

  # POST /griselle_cart/increment
  def increment
    mutate_qty!(params[:line_id].to_s, +1)
    redirect_to griselle_cart_path
  end

  # POST /griselle_cart/decrement
  def decrement
    mutate_qty!(params[:line_id].to_s, -1)
    redirect_to griselle_cart_path
  end

  # POST /griselle_cart/remove
  def remove
    cart = session[:griselle_cart].is_a?(Array) ? session[:griselle_cart] : []
    cart.reject! { |l| l.is_a?(Hash) && l[:id].to_s == params[:line_id].to_s }
    session[:griselle_cart] = cart
    redirect_to griselle_cart_path
  end

  # POST /griselle_cart/checkout
  def checkout
    payment_method = %w[cash transfer].include?(params[:payment_method]) ? params[:payment_method] : "cash"
    cart = session[:griselle_cart].is_a?(Array) ? session[:griselle_cart] : []
    if cart.blank?
      redirect_to griselle_cart_path, alert: "No hay items en el carrito."; return
    end

    # Producto genérico para items personalizados
    service_product = Product.find_or_create_by!(name: "Servicio Griselle") do |p|
      p.price_cents = 0
      p.cost_cents  = 0 if p.respond_to?(:cost_cents=)
      p.stock       = 0 if p.respond_to?(:stock=)
      p.category    = "servicios" if p.respond_to?(:category=)
    end

    total_cents = cart.sum { |l| l[:price_cents].to_i * l[:qty].to_i }

    sale = StoreSale.create!(
      user: current_user,
      payment_method: payment_method,
      total_cents: total_cents,
      occurred_at: Time.current
    )

    cart.each do |l|
      qty  = l[:qty].to_i
      unit = l[:price_cents].to_i
      next if qty <= 0 || unit <= 0
      sale.store_sale_items.create!(
        product_id: service_product.id,
        quantity: qty,
        unit_price_cents: unit,
        note: l[:name] # si tu modelo no tiene `note`, puedes quitar esta línea
      )
    end

    session[:griselle_cart] = []
    redirect_to griselle_cart_path, notice: "Venta registrada."
  rescue => e
    redirect_to griselle_cart_path, alert: "No se pudo realizar el cobro: #{e.message}"
  end

  private

  def mutate_qty!(line_id, delta)
    cart = session[:griselle_cart].is_a?(Array) ? session[:griselle_cart] : []
    line = cart.find { |l| l.is_a?(Hash) && l[:id].to_s == line_id.to_s }
    return unless line

    new_qty = line[:qty].to_i + delta.to_i
    if new_qty > 0
      line[:qty] = new_qty
    else
      cart.delete(line)
    end
    session[:griselle_cart] = cart
  end
end

# app/controllers/griselle_cart_controller.rb
class GriselleCartController < ApplicationController
  before_action :authenticate_user!  # ✅ cualquiera con sesión puede entrar

  # Vista principal del carrito de clases
  def show
    @cart = session[:griselle_cart] || {}
  end

  def add
    pid = params[:product_id].to_i
    qty = params[:quantity].to_i
    qty = 1 if qty <= 0

    session[:griselle_cart] ||= {}
    session[:griselle_cart][pid] = (session[:griselle_cart][pid].to_i + qty)

    redirect_to griselle_cart_path, notice: "Agregado."
  end

  def increment
    pid = params[:product_id].to_i
    session[:griselle_cart] ||= {}
    session[:griselle_cart][pid] = session[:griselle_cart][pid].to_i + 1
    redirect_to griselle_cart_path
  end

  def decrement
    pid = params[:product_id].to_i
    session[:griselle_cart] ||= {}
    current = session[:griselle_cart][pid].to_i - 1
    if current > 0
      session[:griselle_cart][pid] = current
    else
      session[:griselle_cart].delete(pid)
    end
    redirect_to griselle_cart_path
  end

  def remove
    pid = params[:product_id].to_i
    session[:griselle_cart] ||= {}
    session[:griselle_cart].delete(pid)
    redirect_to griselle_cart_path
  end

  def checkout
    payment_method = params[:payment_method].in?(%w[cash transfer]) ? params[:payment_method] : "cash"
    cart = session[:griselle_cart] || {}
    if cart.blank?
      redirect_to griselle_cart_path, alert: "No hay items en el carrito."
      return
    end

    # Aquí asume que cobras “clases” como venta de tienda normal (StoreSale)
    # Si tu flujo es distinto, deja tu lógica original.
    total_cents = 0
    items_attrs = []

    Product.where(id: cart.keys.map(&:to_i)).find_each do |p|
      qty = cart[p.id.to_s].to_i
      next if qty <= 0
      line_cents = p.price_cents.to_i * qty
      total_cents += line_cents
      items_attrs << { product_id: p.id, quantity: qty, unit_price_cents: p.price_cents.to_i }
      # Si las “clases” no afectan stock, elimina esto:
      p.update!(stock: [p.stock.to_i - qty, 0].max)
    end

    ss = StoreSale.create!(
      user: current_user,
      payment_method: payment_method,  # enum
      total_cents: total_cents,
      occurred_at: Time.current
    )

    items_attrs.each do |attrs|
      ss.store_sale_items.create!(attrs)
    end

    session[:griselle_cart] = {}
    redirect_to griselle_cart_path, notice: "Venta registrada."
  rescue => e
    redirect_to griselle_cart_path, alert: "No se pudo realizar el cobro: #{e.message}"
  end
end

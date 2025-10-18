class CartController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_cart

  def show; end

  def add
    product = Product.find(params[:product_id])
    bump(product.id)
    redirect_back fallback_location: authenticated_root_path
  end

  def increment
    product = Product.find(params[:product_id])
    bump(product.id)
    redirect_back fallback_location: authenticated_root_path
  end

  def decrement
    product = Product.find(params[:product_id])
    key = product.id.to_s
    if @cart[key].to_i > 1
      @cart[key] = @cart[key].to_i - 1
    else
      @cart.delete(key)
    end
    save_cart
    redirect_back fallback_location: authenticated_root_path
  end

  def remove
    @cart.delete(params[:product_id].to_s)
    save_cart
    redirect_back fallback_location: authenticated_root_path
  end

  def checkout
    # 1) Validaciones previas (si algo falla, levantamos error explícito)
    raise "Carrito vacío" if @cart.blank?

    payment = params[:payment_method].to_s
    raise "Falta método de pago (cash o transfer)" unless %w[cash transfer].include?(payment)

    items = build_items(@cart) # => [{product:, quantity:, unit_price_cents:}]
    raise "No hay productos válidos en el carrito" if items.empty?

    # DEBUG: loguea lo que vamos a procesar
    Rails.logger.debug("[CHECKOUT] payment=#{payment} items=#{items.map { |it| { id: it[:product].id, qty: it[:quantity], price: it[:unit_price_cents] } }}")

    # 2) Transacción con lock de filas de productos
    ActiveRecord::Base.transaction do
      locked = Product.lock.where(id: items.map { |it| it[:product].id }).index_by(&:id)

      items.each do |it|
        p = locked[it[:product].id]
        raise "Producto no encontrado (ID=#{it[:product].id})" unless p
        raise "Stock insuficiente para #{p.name} (stock=#{p.stock}, qty=#{it[:quantity]})" if p.stock < it[:quantity]
      end

      sale = StoreSale.create!(
        user: current_user,
        payment_method: payment,  # enum acepta "cash"/"transfer"
        total_cents: 0,
        occurred_at: Time.current
      )

      total_cents = 0

      items.each do |it|
        p = locked[it[:product].id]
        qty = it[:quantity]
        line_cents = qty * it[:unit_price_cents]

        StoreSaleItem.create!(
          store_sale: sale,
          product: p,
          quantity: qty,
          unit_price_cents: it[:unit_price_cents]
        )

        p.update!(stock: p.stock - qty)
        total_cents += line_cents
      end

      sale.update!(total_cents: total_cents)
    end

    # 3) Éxito: limpiar carrito y volver
    session[:cart] = {}
    redirect_back fallback_location: authenticated_root_path
  end

  # ===== privados =====
  private

  def ensure_cart
    session[:cart] ||= {}
    @cart = session[:cart]
  end

  def save_cart
    session[:cart] = @cart
  end

  def bump(product_id)
    key = product_id.to_s
    @cart[key] ||= 0
    @cart[key] = @cart[key].to_i + 1
    save_cart
  end

  def build_items(cart_hash)
    ids = cart_hash.keys.map(&:to_i)
    db = Product.where(id: ids).index_by(&:id)
    ids.map do |pid|
      p = db[pid]
      q = cart_hash[pid.to_s].to_i
      next unless p && q.positive?
      { product: p, quantity: q, unit_price_cents: p.price_cents.to_i }
    end.compact
  end
end

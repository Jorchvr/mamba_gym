class GriselleCartController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_griselle!
  before_action :load_cart

  ITEMS = {
    "jumping" => { name: "Jumping", price_cents: 1500 },
    "baile"   => { name: "Baile",   price_cents: 1500 },
    "zumba"   => { name: "Zumba",   price_cents: 1500 }
  }.freeze

  def show; end

  # params: id (jumping|baile|zumba|custom), description (si custom), amount (pesos)
  def add
    if params[:id].present? && ITEMS.key?(params[:id])
      line = line_for(params[:id], ITEMS[params[:id]][:name], ITEMS[params[:id]][:price_cents])
    elsif params[:id] == "custom"
      desc   = params[:description].to_s.strip
      amount = params[:amount].to_s.strip
      unless desc.present? && amount.present? && amount.to_f > 0
        flash[:cart_alert] = "Para precio personalizado indica descripción y monto."
        return redirect_to griselle_cart_path
      end
      cents = (amount.to_f * 100).round
      uid   = "custom-#{SecureRandom.hex(4)}"
      line  = line_for(uid, desc, cents)
    else
      flash[:cart_alert] = "Artículo inválido."
      return redirect_to griselle_cart_path
    end

    line[:qty] = line[:qty].to_i + 1
    persist_cart!
    flash[:cart_notice] = "Agregado: #{line[:name]}"
    redirect_to griselle_cart_path
  end

  def increment
    if (idx = find_index(params[:line_id]))
      @cart[idx][:qty] = @cart[idx][:qty].to_i + 1
      persist_cart!
    end
    redirect_to griselle_cart_path
  end

  def decrement
    if (idx = find_index(params[:line_id]))
      @cart[idx][:qty] = @cart[idx][:qty].to_i - 1
      @cart.delete_at(idx) if @cart[idx][:qty].to_i <= 0
      persist_cart!
    end
    redirect_to griselle_cart_path
  end

  def remove
    if (idx = find_index(params[:line_id]))
      @cart.delete_at(idx)
      persist_cart!
    end
    redirect_to griselle_cart_path
  end

  # params: payment_method (cash|transfer)
  def checkout
    if @cart.blank?
      flash[:cart_alert] = "El carrito está vacío."
      return redirect_to griselle_cart_path
    end

    pm = params[:payment_method].in?(%w[cash transfer]) ? params[:payment_method] : "cash"
    total_cents = @cart.sum { |l| l[:price_cents].to_i * l[:qty].to_i }

    Sale.create!(
      amount_cents:  total_cents,
      occurred_at:   Time.current,
      payment_method: pm,      # enum: "cash" o "transfer"
      user:          current_user,
      client:        nil       # venta suelta de la mini-tienda
      # membership_type: nil   # opcional, si no aplica
    )

    session[:griselle_cart] = []
    flash[:cart_notice] = "Venta registrada ($#{(total_cents / 100.0).round(2)}) por #{pm == 'cash' ? 'Efectivo' : 'Transferencia'}."
    redirect_to griselle_cart_path
  end

  private

  def ensure_griselle!
    unless current_user&.email == "griselle@example.com"
      redirect_to authenticated_root_path, alert: "Sección exclusiva." and return
    end
  end

  def load_cart
    raw = session[:griselle_cart]
    raw = [] unless raw.is_a?(Array)
    @cart = raw.map do |l|
      {
        id:           l.is_a?(Hash) ? (l[:id] || l["id"]) : nil,
        name:         l.is_a?(Hash) ? (l[:name] || l["name"]) : nil,
        price_cents:  l.is_a?(Hash) ? (l[:price_cents] || l["price_cents"]).to_i : 0,
        qty:          l.is_a?(Hash) ? (l[:qty] || l["qty"]).to_i : 0
      }
    end
    @cart.select! { |l| l[:id].present? && l[:name].present? }
    persist_cart!
  end

  def persist_cart!
    session[:griselle_cart] = @cart
  end

  def line_for(id, name, price_cents)
    line = @cart.find { |l| l[:id] == id }
    unless line
      line = { id: id, name: name, price_cents: price_cents.to_i, qty: 0 }
      @cart << line
    end
    line
  end

  def find_index(line_id)
    return nil if line_id.blank?
    @cart.index { |l| l[:id] == line_id }
  end
end

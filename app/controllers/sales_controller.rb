# app/controllers/sales_controller.rb
class SalesController < ApplicationController
  before_action :authenticate_user!

  # GET /sales
  # Por defecto: ventas del usuario actual en la fecha indicada (o hoy).
  # Superusuario puede ver otro usuario con ?user_id=ID o todas con ?all=1
  def index
    @date =
      if params[:date].present?
        Date.parse(params[:date]) rescue Time.zone.today
      else
        Time.zone.today
      end

    from = @date.beginning_of_day
    to   = @date.end_of_day

    # Por defecto filtra por usuario actual
    user_scope_id = current_user.id

    # Si es superusuario, puede ver todas (?all=1) o por user_id específico
    if superuser?
      if params[:all].present?
        user_scope_id = nil
      elsif params[:user_id].present?
        user_scope_id = params[:user_id].to_i
      end
    end

    # Ventas de membresía (Sale)
    sales_scope =
      if defined?(Sale)
        Sale.where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to)
      else
        Sale.none
      end

    # Ventas de tienda (StoreSale), incluyendo Griselle
    store_sales_scope =
      if defined?(StoreSale)
        StoreSale.where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", from, to)
      else
        StoreSale.none
      end

    if user_scope_id
      sales_scope       = sales_scope.where(user_id: user_scope_id)
      store_sales_scope = store_sales_scope.where(user_id: user_scope_id)
    end

    @transactions = []

    sales_scope.includes(:user, :client).find_each do |s|
      @transactions << {
        kind: :membership,
        id: s.id,
        at: (s.occurred_at || s.created_at),
        user: s.user,
        client: s.client,
        amount_cents: s.amount_cents.to_i,
        payment_method: s.payment_method,
        label: "Membresía #{s.membership_type}"
      }
    end

    store_sales_scope.includes(:user).find_each do |ss|
      @transactions << {
        kind: :store,
        id: ss.id,
        at: (ss.occurred_at || ss.created_at),
        user: ss.user,
        client: nil,
        amount_cents: ss.total_cents.to_i,
        payment_method: ss.payment_method,
        label: "Tienda (##{ss.id})"
      }
    end

    @transactions.sort_by! { |h| h[:at] }
    @count         = @transactions.size
    @total_cents   = @transactions.sum { |h| h[:amount_cents] }
    @selected_user = user_scope_id ? User.find_by(id: user_scope_id) : nil
  end

  def show
    # ...
  end

  # =====================================================
  # SECCIÓN PROTEGIDA: AJUSTES / VENTAS NEGATIVAS (SOLO TIENDA)
  # =====================================================

  # GET /sales/adjustments
  # 1) Si no está desbloqueado, muestra formulario de código.
  # 2) Si ya está desbloqueado, muestra ventas de TIENDA del día del usuario + botón de venta negativa.
  def adjustments
    @date = Time.zone.today
    @from = @date.beginning_of_day
    @to   = @date.end_of_day

    unless session[:store_adjustments_unlocked]
      @needs_unlock = true
      return
    end

    scope = StoreSale.where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", @from, @to)
    scope = scope.where(user_id: current_user.id) unless superuser?

    @store_sales = scope.includes(:user, store_sale_items: :product)
  end

  # POST /sales/unlock_adjustments
  # Código secreto: 010101
  def unlock_adjustments
    code     = params[:security_code].to_s.strip
    expected = "010101"

    ok =
      code.present? &&
      expected.present? &&
      code.length == expected.length && # evita error en secure_compare
      ActiveSupport::SecurityUtils.secure_compare(code, expected)

    if ok
      session[:store_adjustments_unlocked] = true
      redirect_to adjustments_sales_path, notice: "Sección de ajustes de tienda desbloqueada."
    else
      session[:store_adjustments_unlocked] = false
      redirect_to adjustments_sales_path, alert: "Código de seguridad incorrecto."
    end
  end

  # POST /sales/reverse_transaction
  # Crea una venta NEGATIVA de TIENDA para anular una venta de StoreSale.
  def reverse_transaction
    unless session[:store_adjustments_unlocked]
      redirect_to adjustments_sales_path, alert: "Debes ingresar el código de seguridad."
      return
    end

    ss_id    = params[:store_sale_id].to_i
    original = StoreSale.includes(:store_sale_items).find_by(id: ss_id)

    unless original
      redirect_to adjustments_sales_path, alert: "Venta de tienda no encontrada."
      return
    end

    # Si no es superusuario, solo puede ajustar ventas propias
    if !superuser? && original.user_id != current_user.id
      redirect_to adjustments_sales_path, alert: "No puedes ajustar ventas de otros usuarios."
      return
    end

    reason = params[:reason].to_s.strip

    StoreSale.transaction do
      # Atributos básicos de la venta negativa
      attrs = {
        user:           current_user,
        payment_method: original.payment_method,
        total_cents:    -original.total_cents.to_i,
        occurred_at:    Time.current
      }

      # Solo si ALGÚN DÍA agregas columna metadata en store_sales
      if StoreSale.column_names.include?("metadata")
        attrs[:metadata] = { reversal_of_id: original.id, reason: reason }
      end

      reversal = StoreSale.create!(attrs)

      # Items espejo en negativo
      original.store_sale_items.find_each do |item|
        reversal.store_sale_items.create!(
          product_id:        item.product_id,
          quantity:          item.quantity,
          unit_price_cents: -item.unit_price_cents.to_i,
          description:      (item.respond_to?(:description) ? item.description : nil)
        )
      end
    end

    redirect_to adjustments_sales_path, notice: "Venta negativa creada para anular la venta de tienda ##{original.id}."
  rescue => e
    redirect_to adjustments_sales_path, alert: "No se pudo crear la venta negativa: #{e.message}"
  end

  private

  def superuser?
    current_user.respond_to?(:superuser?) ? current_user.superuser? : false
  end
end

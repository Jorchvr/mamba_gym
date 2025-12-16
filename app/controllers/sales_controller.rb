class SalesController < ApplicationController
  before_action :authenticate_user!

  # GET /sales
  def index
    @date =
      if params[:date].present?
        Date.parse(params[:date]) rescue Time.zone.today
      else
        Time.zone.today
      end

    from = @date.beginning_of_day
    to   = @date.end_of_day

    user_scope_id = current_user.id

    if superuser?
      if params[:all].present?
        user_scope_id = nil
      elsif params[:user_id].present?
        user_scope_id = params[:user_id].to_i
      end
    end

    sales_scope =
      if defined?(Sale)
        Sale.where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to)
      else
        Sale.none
      end

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
  end

  # =====================================================
  # SECCIÓN PROTEGIDA: AJUSTES / VENTAS NEGATIVAS
  # =====================================================

  def adjustments
    @date = Time.zone.today
    @from = @date.beginning_of_day
    @to   = @date.end_of_day

    unless session[:store_adjustments_unlocked]
      @needs_unlock = true
      return
    end

    # Mostramos TODO para facilitar el debug, sin filtrar por usuario
    store_scope = StoreSale.where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", @from, @to)
    membership_scope = Sale.where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", @from, @to)

    # COMENTADO: Filtro de usuario desactivado para que veas todas las ventas
    # unless superuser?
    #   store_scope      = store_scope.where(user_id: current_user.id)
    #   membership_scope = membership_scope.where(user_id: current_user.id)
    # end

    @store_sales = store_scope.includes(:user, store_sale_items: :product).order(id: :desc)
    @membership_sales = membership_scope.includes(:user, :client).order(id: :desc)
  end

  # POST /sales/unlock_adjustments
  def unlock_adjustments
    code     = params[:security_code].to_s.strip
    expected = "010101"

    if code == expected || ActiveSupport::SecurityUtils.secure_compare(code, expected)
      session[:store_adjustments_unlocked] = true
      redirect_to adjustments_sales_path, notice: "Sección desbloqueada."
    else
      session[:store_adjustments_unlocked] = false
      redirect_to adjustments_sales_path, alert: "Código incorrecto."
    end
  end

  # POST /sales/reverse_transaction
  def reverse_transaction
    # 1. Verificar desbloqueo
    unless session[:store_adjustments_unlocked]
      redirect_to adjustments_sales_path, alert: "Ingresa el código primero."
      return
    end

    reason = params[:reason].to_s.strip
    puts ">>> INICIANDO REVERSIÓN. Params: #{params.inspect}"

    # ==========================================
    # CASO A: REVERTIR MEMBRESÍA (Sale)
    # ==========================================
    if params[:sale_id].present?
      puts ">>> BUSCANDO SALE ID: #{params[:sale_id]}"
      original = Sale.find_by(id: params[:sale_id])

      if original.nil?
        redirect_to adjustments_sales_path, alert: "Error: No se encontró la venta #{params[:sale_id]}"
        return
      end

      # --- DESACTIVADO TEMPORALMENTE ---
      # Si la venta ya es negativa, no dejarla hacer negativa otra vez
      # if original.amount_cents <= 0
      #   redirect_to adjustments_sales_path, alert: "Esa venta ya es una devolución."
      #   return
      # end

      # --- DESACTIVADO TEMPORALMENTE ---
      # Restricción de usuario: Ahora cualquiera puede borrar lo de cualquiera
      # if !superuser? && original.user_id != current_user.id
      #   redirect_to adjustments_sales_path, alert: "No tienes permiso para borrar ventas de otros."
      #   return
      # end

      puts ">>> INTENTANDO CREAR REVERSAL PARA SALE #{original.id}"

      reversal = Sale.new(
        user:           current_user,
        client_id:      original.client_id,
        payment_method: original.payment_method,
        amount_cents:   -original.amount_cents.to_i, # Negativo
        membership_type: "DEVOLUCIÓN - #{original.membership_type}",
        occurred_at:    Time.current
      )

      # Forzamos duration 0
      reversal.duration_days = 0 if reversal.respond_to?(:duration_days=)

      # GUARDADO FORZOSO SIN VALIDACIONES
      reversal.save!(validate: false)

      puts ">>> ÉXITO: Reversal creada con ID #{reversal.id}"
      redirect_to adjustments_sales_path, notice: "Devolución de membresía exitosa."

    # ==========================================
    # CASO B: REVERTIR TIENDA (StoreSale)
    # ==========================================
    elsif params[:store_sale_id].present?
      puts ">>> BUSCANDO STORE SALE ID: #{params[:store_sale_id]}"
      original = StoreSale.includes(store_sale_items: :product).find_by(id: params[:store_sale_id])

      if original.nil?
        redirect_to adjustments_sales_path, alert: "Venta de tienda no encontrada."
        return
      end

      # --- DESACTIVADO TEMPORALMENTE ---
      # if !superuser? && original.user_id != current_user.id
      #   redirect_to adjustments_sales_path, alert: "No tienes permiso."
      #   return
      # end

      StoreSale.transaction do
        attrs = {
          user:           current_user,
          payment_method: original.payment_method,
          total_cents:    -original.total_cents.to_i,
          occurred_at:    Time.current
        }

        # Manejo flexible de nota/descripción
        if StoreSale.column_names.include?("note")
          attrs[:note] = "DEVOLUCIÓN ##{original.id}: #{reason}"
        elsif StoreSale.column_names.include?("description")
          attrs[:description] = "DEVOLUCIÓN ##{original.id}: #{reason}"
        end

        reversal = StoreSale.new(attrs)
        reversal.save!(validate: false)

        original.store_sale_items.find_each do |item|
          rev_item = reversal.store_sale_items.build(
            product_id:       item.product_id,
            quantity:         item.quantity,
            unit_price_cents: -item.unit_price_cents.to_i
          )
          rev_item.save!(validate: false)

          if (product = item.product)
            product.update!(stock: product.stock.to_i + item.quantity.to_i)
          end
        end
      end

      redirect_to adjustments_sales_path, notice: "Devolución de tienda exitosa."

    else
      redirect_to adjustments_sales_path, alert: "No se seleccionó ninguna venta."
    end

  rescue => e
    puts ">>> ERROR CRÍTICO: #{e.message}"
    puts e.backtrace.join("\n")
    redirect_to adjustments_sales_path, alert: "Error crítico: #{e.message}"
  end

  # =====================================================================
  # CORTE DEL DÍA
  # =====================================================================
  def corte
    @date = Time.zone.today
    from  = @date.beginning_of_day
    to    = @date.end_of_day

    user = current_user
    @user_name = user.name rescue user.email

    sales = Sale.where("COALESCE(occurred_at, created_at) BETWEEN ? AND ?", from, to)
    store_sales = StoreSale.where("COALESCE(occurred_at, created_at) BETWEEN ? AND ?", from, to)

    unless superuser?
      sales       = sales.where(user_id: user.id)
      store_sales = store_sales.where(user_id: user.id)
    end

    @ops_count = sales.count + store_sales.count
    @member_cents = sales.sum(:amount_cents).to_i
    @store_cents  = store_sales.sum(:total_cents).to_i

    # Cálculo informativo
    adjustments_store = store_sales.where("total_cents < 0").sum(:total_cents).to_i
    adjustments_mem   = sales.where("amount_cents < 0").sum(:amount_cents).to_i
    @adjustments_cents = adjustments_store + adjustments_mem

    @total_cents = @member_cents + @store_cents

    @by_method = { "cash" => 0, "transfer" => 0 }
    sales.each do |s|
      pm = s.payment_method.to_s
      @by_method[pm] += s.amount_cents.to_i if @by_method.key?(pm)
    end
    store_sales.each do |ss|
      pm = ss.payment_method.to_s
      @by_method[pm] += ss.total_cents.to_i if @by_method.key?(pm)
    end

    @checkins_today = Checkin.where(created_at: from..to).count
    @new_clients_today = Client.where(created_at: from..to).count
  end

  private

  def superuser?
    current_user.respond_to?(:superuser?) ? current_user.superuser? : false
  end
end

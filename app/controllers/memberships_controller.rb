class MembershipsController < ApplicationController
  before_action :authenticate_user!

  # === 🟢 PRECIOS ACTUALIZADOS (En centavos) ===
  PRICES = {
    "visit"      => 100_00,  # $100.00
    "week"       => 200_00,  # $200.00
    "month"      => 550_00,  # $550.00
    "couple"     => 950_00,  # $950.00
    "semester"   => 2300_00, # $2,300.00
    "promo_open" => 100_00,  # $100.00
    "promo_feb"  => 250_00   # $250.00
  }.freeze

  # GET /memberships?q=...
  def new
    @query  = params[:q].to_s.strip
    @client = lookup_client(@query) if @query.present?
    @prices = PRICES

    # Calcular fecha sugerida inicial para la vista
    if @client
      # Base: la mayor entre Hoy y su vencimiento actual
      base_date = [ @client.next_payment_on, Date.current ].compact.max
      # Por defecto sugerimos 1 mes más, pero el JS lo cambiará según el botón
      @suggested_next_payment = base_date + 1.month
    end
  end

  # POST /memberships/checkout
  def checkout
    client = Client.find(params[:client_id])

    plan = (params[:plan].presence || params[:membership_type].presence).to_s
    pm   = params[:payment_method].to_s
    payment_method = %w[cash transfer].include?(pm) ? pm : "cash"

    # ¿Es precio personalizado?
    custom_flag = (plan == "custom" || params[:use_custom_price].to_s == "1")

    amount_cents  = nil
    plan_for_enum = nil     # valor para client.membership_type
    meta_variant  = nil     # info extra para metadata

    # ======= LÓGICA DE SELECCIÓN DE PLAN Y PRECIO =======
    if custom_flag
      amount_cents = parse_money_to_cents(params[:custom_price_mxn])
      raise ArgumentError, "Monto personalizado inválido." if amount_cents.nil? || amount_cents <= 0

      plan_for_enum = "month"     # Por defecto lo contamos como mes
      meta_variant  = "custom"
    else
      # Buscar precio en la constante (asegurando string)
      price = PRICES[plan]

      if price.present?
        amount_cents = price
        # Mapear el botón seleccionado al ENUM del modelo Client
        case plan
        when "visit"      then plan_for_enum = "visit"
        when "week"       then plan_for_enum = "week"
        when "month"      then plan_for_enum = "month"
        when "couple"     then plan_for_enum = "couple"
        when "semester"   then plan_for_enum = "semester"
        when "promo_open", "promo_feb"
          plan_for_enum = "month" # Las promos suelen ser mensuales
          meta_variant  = plan    # Guardamos qué promo fue
        else
          plan_for_enum = "month" # Fallback
        end
      else
        return redirect_to memberships_path(q: client.id), alert: "Plan inválido o desconocido."
      end
    end

    new_next = nil

    ApplicationRecord.transaction do
      # 1. Metadata para el historial de ventas
      metadata = {}
      metadata[:variant] = meta_variant if meta_variant.present?

      if custom_flag
        metadata[:custom]      = true
        metadata[:description] = params[:custom_description].to_s.presence
      end

      # 2. Registrar Venta
      Sale.create!(
        client:          client,
        user:            current_user,
        membership_type: plan_for_enum,
        payment_method:  payment_method,
        amount_cents:    amount_cents,
        occurred_at:     Time.current,
        metadata:        metadata
      )

      # 3. Calcular Nueva Fecha de Vencimiento
      # PRIORIDAD: Si el usuario mandó una fecha manual (desde el input date), usamos esa.
      if params[:custom_next_payment_date].present?
        new_next = Date.parse(params[:custom_next_payment_date])
      else
        # RESPALDO: Si no hay fecha manual, calculamos en el servidor
        base_date = [ Date.current, client.next_payment_on ].compact.max

        new_next = case plan
        when "visit"      then base_date + 1.day
        when "week"       then base_date + 1.week
        when "semester"   then base_date + 6.months
        else                   base_date + 1.month # Mes, Pareja, Promos
        end
      end

      # 4. Actualizar Cliente
      client.update!(
        membership_type: plan_for_enum, # Actualizamos su tipo de membresía actual
        enrolled_on:     (client.enrolled_on || Date.current),
        next_payment_on: new_next
      )
    end

    label = custom_flag ? "Personalizado" : plan.humanize.upcase

    redirect_to memberships_path(q: client.id),
      notice: "✅ Cobro exitoso: #{label} ($#{format('%.2f', amount_cents / 100.0)}). Vence: #{new_next&.strftime('%d/%m/%Y')}."

  rescue ActiveRecord::RecordNotFound
    redirect_to memberships_path, alert: "Cliente no encontrado."
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to memberships_path(q: params[:client_id] || params[:q]),
      alert: "Error al cobrar: #{e.message}"
  rescue => e
    redirect_to memberships_path(q: params[:client_id] || params[:q]),
      alert: "Error inesperado: #{e.message}"
  end

  private

  # Busca por ID exacto o por nombre (primer match)
  def lookup_client(q)
    if q.to_i.to_s == q
      Client.find_by(id: q.to_i)
    else
      Client.where("LOWER(name) LIKE ?", "%#{q.downcase}%").first
    end
  end

  # Convierte "1,200.50" -> 120050
  def parse_money_to_cents(input)
    s = input.to_s.strip
    return nil if s.blank?
    s = s.gsub(/[^\d.,-]/, "")
    if s.include?(",") && s.include?(".")
      s = s.delete(",") # Asume formato 1,200.00
    else
      s = s.tr(",", ".") # Asume formato 1200,00
    end
    (s.to_f * 100).round
  end
end

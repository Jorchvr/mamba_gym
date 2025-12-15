class MembershipsController < ApplicationController
  before_action :authenticate_user!

  # Precios en centavos
  PRICES = {
    day:           3000,   # $30.00
    week:          12000,  # $120.00
    month:         26500,  # $265.00 (compatibilidad)
    month_late:    26500,  # $265.00  (Mes atraso)
    month_on_time: 25000   # $250.00  (Mensualidad puntual)
  }.freeze

  # GET /memberships?q=...
  def new
    @query  = params[:q].to_s.strip
    @client = lookup_client(@query) if @query.present?
    @prices = PRICES

    # --- MODIFICACIÓN: Calcular fecha sugerida inicial ---
    if @client
      # Base: la mayor entre Hoy y su vencimiento actual (para no comerse días)
      base_date = [ @client.next_payment_on, Date.current ].compact.max
      # Por defecto sugerimos 1 mes más, pero será editable en la vista
      @suggested_next_payment = base_date + 1.month
    end
  end

  # POST /memberships/checkout
  def checkout
    client = Client.find(params[:client_id])

    plan = (params[:plan].presence || params[:membership_type].presence).to_s
    pm   = params[:payment_method].to_s
    payment_method = %w[cash transfer].include?(pm) ? pm : "cash"

    # ¿Se está usando precio personalizado?
    custom_flag = (plan == "custom" || params[:use_custom_price].to_s == "1")

    amount_cents  = nil
    plan_for_enum = nil     # enum day|week|month
    month_variant = nil     # late | on_time | custom

    # ======= PERSONALIZADO (tratar como 1 MES) =======
    if custom_flag
      amount_cents = parse_money_to_cents(params[:custom_price_mxn])
      raise ArgumentError, "Monto personalizado inválido." if amount_cents.nil? || amount_cents <= 0

      plan_for_enum = "month"     # 🔥 cuenta como un mes
      month_variant = "custom"    # lo marcamos como variante personalizada
    else
      # ======= PLANES FIJOS (día, semana, mes atraso/puntual) =======
      amount_cents, plan_for_enum, month_variant =
        case plan
        when "day"           then [ PRICES[:day],           "day",   nil ]
        when "week"          then [ PRICES[:week],          "week",  nil ]
        when "month_late"    then [ PRICES[:month_late],    "month", "late" ]
        when "month_on_time" then [ PRICES[:month_on_time], "month", "on_time" ]
        else
          return redirect_to memberships_path(q: client.id), alert: "Plan inválido."
        end
    end

    new_next = nil

    ApplicationRecord.transaction do
      # Metadata extra
      metadata = {}
      metadata[:month_variant] = month_variant if month_variant.present?
      if custom_flag
        metadata[:custom]       = true
        metadata[:description]  = params[:custom_description].to_s.presence
      end

      # Registro de la venta
      Sale.create!(
        client:          client,
        user:            current_user,
        membership_type: plan_for_enum,   # enum day|week|month
        payment_method:  payment_method,  # enum cash|transfer
        amount_cents:    amount_cents,
        occurred_at:     Time.current,
        metadata:        metadata
      )

      # --- MODIFICACIÓN: Prioridad a fecha manual ---
      if params[:custom_next_payment_date].present?
        new_next = Date.parse(params[:custom_next_payment_date])
      else
        # Cálculo automático original (solo si no se envió fecha)
        base_date = [ Date.current, client.next_payment_on ].compact.max
        new_next  = case plan_for_enum
        when "day"   then base_date + 1.day
        when "week"  then base_date + 1.week
        when "month" then base_date + 1.month
        end
      end
      # ---------------------------------------------

      client.update!(
        enrolled_on:     (client.enrolled_on || Date.current),
        next_payment_on: new_next
      )
    end

    label =
      if custom_flag
        "Mensualidad personalizada"
      else
        case plan
        when "month_late"    then "Mes (atraso)"
        when "month_on_time" then "Mensualidad (puntual)"
        else
          plan.humanize
        end
      end

    redirect_to memberships_path(q: client.id),
      notice: "Pago registrado (#{label}) por $#{format('%.2f', amount_cents / 100.0)}. Próximo pago: #{new_next}."

  rescue ActiveRecord::RecordNotFound
    redirect_to memberships_path, alert: "Cliente no encontrado."
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to memberships_path(q: params[:client_id] || params[:q]),
      alert: "No se pudo completar el cobro: #{e.message}"
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

  # "1,200.50" / "1200,50" / "$1200.50" => centavos
  def parse_money_to_cents(input)
    s = input.to_s.strip
    return nil if s.blank?
    s = s.gsub(/[^\d.,-]/, "")
    if s.include?(",") && s.include?(".")
      s = s.delete(",")
    else
      s = s.tr(",", ".")
    end
    (s.to_f * 100).round
  end
end

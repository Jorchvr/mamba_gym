class MembershipsController < ApplicationController
  before_action :authenticate_user!

  # === 💰 LISTA MAESTRA DE PRECIOS (En Centavos) ===
  # Esto es la "verdad absoluta". Lo que diga aquí es lo que se cobra.
  PRICES = {
    "visit"      => 100_00,   # $100.00
    "week"       => 200_00,   # $200.00
    "month"      => 550_00,   # $550.00
    "couple"     => 950_00,   # $950.00
    "semester"   => 2300_00,  # $2300.00
    "promo_open" => 100_00,   # Promo Apertura $100
    "promo_feb"  => 250_00    # Promo Febrero $250
  }.freeze

  # GET /memberships
  def index
    # Redirige al new si intentan entrar al index directo, o maneja búsqueda aquí
    redirect_to new_membership_path
  end

  # GET /memberships/new?q=...
  def new
    @query  = params[:q].to_s.strip
    @client = lookup_client(@query) if @query.present?

    # Pasamos los precios a la vista para pintarlos en los botones si es necesario
    @prices = PRICES
  end

  # POST /memberships/checkout
  def checkout
    client = Client.find(params[:client_id])

    # 1. Identificar el plan seleccionado (visit, week, month, etc.)
    plan_key = params[:plan].to_s

    # 2. Obtener el precio desde la constante (SEGURIDAD: No confiamos en el HTML)
    amount_cents = PRICES[plan_key]

    # Si el plan no existe en nuestra lista, error.
    if amount_cents.nil?
      return redirect_to memberships_path(q: client.id), alert: "⚠️ Error: Debes seleccionar un plan válido."
    end

    # 3. Calcular Fechas Automáticamente (Cálculo sagrado del servidor)
    # Base: Si ya tenía fecha futura, sumamos desde ahí. Si estaba vencido, sumamos desde hoy.
    base_date = [ client.next_payment_on, Date.current ].compact.max
    new_expiration_date = calculate_expiration(base_date, plan_key)

    # 4. Determinar método de pago
    pm = params[:payment_method] == "transfer" ? "transfer" : "cash"

    # 5. Mapear nombre del plan al ENUM del modelo Client
    # El modelo solo entiende: day, week, month, couple, semester, visit
    model_membership_type = map_plan_to_model(plan_key)

    ActiveRecord::Base.transaction do
      # A) Guardar Venta
      Sale.create!(
        client: client,
        user: current_user,
        membership_type: model_membership_type,
        payment_method: pm,
        amount_cents: amount_cents,
        occurred_at: Time.current,
        metadata: { plan_original: plan_key } # Guardamos si fue promo_open, promo_feb, etc.
      )

      # B) Actualizar Cliente (Membresía y Fechas)
      client.update!(
        membership_type: model_membership_type,
        enrolled_on: (client.enrolled_on || Date.current),
        next_payment_on: new_expiration_date
      )
    end

    redirect_to memberships_path(q: client.id),
      notice: "✅ Cobrado: $#{amount_cents / 100}.00 (#{plan_key.humanize}). Vence: #{new_expiration_date.strftime('%d/%m/%Y')}"

  rescue ActiveRecord::RecordNotFound
    redirect_to memberships_path, alert: "❌ Cliente no encontrado."
  rescue => e
    redirect_to memberships_path(q: params[:client_id]), alert: "❌ Error inesperado: #{e.message}"
  end

  private

  # Lógica de calendario estricta
  def calculate_expiration(start_date, plan)
    case plan
    when "visit"
      start_date + 1.day
    when "week"
      start_date + 1.week
    when "month", "couple", "promo_open", "promo_feb"
      start_date + 1.month
    when "semester"
      start_date + 6.months
    else
      start_date + 1.month # Fallback por seguridad
    end
  end

  # Traduce "promo_open" -> "month" para que el modelo no se queje
  def map_plan_to_model(plan)
    case plan
    when "visit"      then "visit"
    when "week"       then "week"
    when "month"      then "month"
    when "couple"     then "couple"
    when "semester"   then "semester"
    when "promo_open", "promo_feb"
      "month" # Las promos de dinero se consideran membresía mensual en el sistema
    else
      "month"
    end
  end

  def lookup_client(q)
    if q.to_i.to_s == q
      Client.find_by(id: q.to_i)
    else
      Client.where("LOWER(name) LIKE ?", "%#{q.downcase}%").first
    end
  end
end

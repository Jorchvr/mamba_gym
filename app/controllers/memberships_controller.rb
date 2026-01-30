class MembershipsController < ApplicationController
  before_action :authenticate_user!

  # === 💰 LISTA DE PRECIOS ACTUALIZADA ===
  PRICES = {
    "visit"      => 100_00,   # $100
    "week"       => 200_00,   # $200
    "month"      => 500_00,   # $500 (Efectivo)
    "month_card" => 550_00,   # $550 (Tarjeta)
    "couple"     => 950_00,   # $950
    "semester"   => 2300_00,  # $2300
    "promo_open" => 100_00    # Apertura $100
  }.freeze

  def index
    redirect_to new_membership_path
  end

  def new
    @query  = params[:q].to_s.strip
    @client = lookup_client(@query) if @query.present?
    @prices = PRICES
  end

  def checkout
    client = Client.find(params[:client_id])
    plan_key = params[:plan].to_s

    # Lógica precio personalizado
    if plan_key == "custom"
      amount_str = params[:custom_amount].to_s.gsub(/[^0-9.]/, "")
      amount_cents = (amount_str.to_f * 100).to_i
      if amount_cents <= 0
        return redirect_to memberships_path(q: client.id), alert: "⚠️ Error: Ingresa un monto válido."
      end
    else
      amount_cents = PRICES[plan_key]
    end

    if amount_cents.nil?
      return redirect_to memberships_path(q: client.id), alert: "⚠️ Error: Selecciona un plan válido."
    end

    base_date = [ client.next_payment_on, Date.current ].compact.max
    new_expiration_date = calculate_expiration(base_date, plan_key)

    # Si seleccionó el botón específico de tarjeta O el radio button de tarjeta
    force_card = (plan_key == "month_card")
    pm = (force_card || params[:payment_method] == "card") ? "card" : "cash"

    model_membership_type = map_plan_to_model(plan_key)

    ActiveRecord::Base.transaction do
      Sale.create!(
        client: client,
        user: current_user,
        membership_type: model_membership_type,
        payment_method: pm,
        amount_cents: amount_cents,
        occurred_at: Time.current,
        metadata: { plan_original: plan_key }
      )

      client.update!(
        membership_type: model_membership_type,
        enrolled_on: (client.enrolled_on || Date.current),
        next_payment_on: new_expiration_date
      )
    end

    redirect_to memberships_path(q: client.id),
      notice: "✅ Cobrado: $#{amount_cents / 100.0}. Vence: #{new_expiration_date.strftime('%d/%m/%Y')}"

  rescue ActiveRecord::RecordNotFound
    redirect_to memberships_path, alert: "❌ Cliente no encontrado."
  rescue => e
    redirect_to memberships_path(q: params[:client_id]), alert: "❌ Error: #{e.message}"
  end

  private

  def calculate_expiration(start_date, plan)
    case plan
    when "visit"      then start_date + 1.day
    when "week"       then start_date + 1.week
    when "semester"   then start_date + 6.months
    when "promo_open" then start_date + 1.month # Apertura suele ser un mes
    else                   start_date + 1.month # Mes, Tarjeta, Custom
    end
  end

  def map_plan_to_model(plan)
    case plan
    when "visit"      then "visit"
    when "week"       then "week"
    when "month"      then "month"
    when "month_card" then "month" # Se guarda como mes normal
    when "couple"     then "couple"
    when "semester"   then "semester"
    when "promo_open" then "promo"
    when "custom"     then "promo"
    else                   "month"
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

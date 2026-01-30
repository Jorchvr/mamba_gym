class MembershipsController < ApplicationController
  before_action :authenticate_user!

  # === 💰 LISTA DE PRECIOS ===
  PRICES = {
    "visit"      => 100_00,   # $100.00
    "week"       => 200_00,   # $200.00
    "month"      => 550_00,   # $550.00
    "couple"     => 950_00,   # $950.00
    "semester"   => 2300_00,  # $2300.00
    "promo_open" => 100_00,   # Promo $100
    "promo_feb"  => 250_00    # Promo $250
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
    amount_cents = PRICES[plan_key]

    if amount_cents.nil?
      return redirect_to memberships_path(q: client.id), alert: "⚠️ Error: Selecciona un plan válido."
    end

    # Cálculo de fechas
    base_date = [ client.next_payment_on, Date.current ].compact.max
    new_expiration_date = calculate_expiration(base_date, plan_key)

    # Método de pago
    pm = params[:payment_method] == "card" ? "card" : "cash"

    # Mapeo
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
      notice: "✅ Cobrado: $#{amount_cents / 100}.00 (#{plan_key.humanize}). Vence: #{new_expiration_date.strftime('%d/%m/%Y')}"

  rescue ActiveRecord::RecordNotFound
    redirect_to memberships_path, alert: "❌ Cliente no encontrado."
  rescue => e
    redirect_to memberships_path(q: params[:client_id]), alert: "❌ Error: #{e.message}"
  end

  private

  def calculate_expiration(start_date, plan)
    case plan
    when "visit"    then start_date + 1.day
    when "week"     then start_date + 1.week
    when "semester" then start_date + 6.months
    else                 start_date + 1.month
    end
  end

  def map_plan_to_model(plan)
    case plan
    when "visit"    then "visit"
    when "week"     then "week"
    when "month"    then "month"
    when "couple"   then "couple"
    when "semester" then "semester"
    else                 "month"
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

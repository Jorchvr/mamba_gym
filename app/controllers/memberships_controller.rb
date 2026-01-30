class MembershipsController < ApplicationController
  before_action :authenticate_user!

  PRICES = {
    "visit"      => 100_00,
    "week"       => 200_00,
    "month"      => 550_00,
    "couple"     => 950_00,
    "semester"   => 2300_00,
    "promo_open" => 100_00,
    "promo_feb"  => 250_00
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

    # === LOGICA PRECIO PERSONALIZADO ===
    if plan_key == "custom"
      # Convertir el input de texto (ej: "450.50") a centavos
      amount_str = params[:custom_amount].to_s.gsub(/[^0-9.]/, "")
      amount_cents = (amount_str.to_f * 100).to_i

      if amount_cents <= 0
        return redirect_to memberships_path(q: client.id), alert: "⚠️ Error: Ingresa un monto válido para la promoción."
      end
    else
      # Precio estándar de la lista
      amount_cents = PRICES[plan_key]
    end

    if amount_cents.nil?
      return redirect_to memberships_path(q: client.id), alert: "⚠️ Error: Selecciona un plan válido."
    end

    base_date = [ client.next_payment_on, Date.current ].compact.max
    new_expiration_date = calculate_expiration(base_date, plan_key)

    pm = params[:payment_method] == "card" ? "card" : "cash"
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
      notice: "✅ Cobrado: $#{amount_cents / 100.0} (#{plan_key.humanize}). Vence: #{new_expiration_date.strftime('%d/%m/%Y')}"

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
    else                 start_date + 1.month # Custom también da 1 mes por defecto
    end
  end

  def map_plan_to_model(plan)
    case plan
    when "visit"    then "visit"
    when "week"     then "week"
    when "month"    then "month"
    when "couple"   then "couple"
    when "semester" then "semester"
    when "custom"   then "promo" # Guardamos como 'promo' en la BD
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

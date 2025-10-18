class MembershipsController < ApplicationController
  before_action :authenticate_user!

  # Ajusta precios aquí (centavos): $15.00 = 1500
  PRICES = {
    day:   1500,   # 1 día
    week:  5000,   # 1 semana
    month: 15000   # 1 mes
  }.freeze

  def new
    @query   = params[:q].to_s.strip
    @client  = lookup_client(@query) if @query.present?
    @prices  = PRICES
  end

  # POST /memberships/checkout
  # params: client_id, plan (day|week|month), payment_method (cash|transfer)
  def checkout
    client = Client.find(params[:client_id])

    plan = params[:plan].to_s
    unless %w[day week month].include?(plan)
      return redirect_to memberships_path(q: client.id), alert: "Plan inválido."
    end

    payment_method = params[:payment_method].in?(%w[cash transfer]) ? params[:payment_method] : "cash"
    amount_cents   = PRICES.fetch(plan.to_sym)

    # Base: si ya tiene próxima en el futuro, extendemos desde ahí; si no, desde hoy.
    base_date = [ Date.current, client.next_payment_on ].compact.max

    new_next =
      case plan
      when "day"   then base_date + 1.day
      when "week"  then base_date + 1.week
      when "month" then base_date + 1.month
      end

    # Venta (usa tus enums en Sale)
    Sale.create!(
      client:          client,
      user:            current_user,
      membership_type: plan,            # enum :membership_type (day|week|month)
      payment_method:  payment_method,  # enum :payment_method  (cash|transfer)
      amount_cents:    amount_cents,
      occurred_at:     Time.current
    )

    # Reactivar/Extender membresía
    client.update!(
      enrolled_on:     (client.enrolled_on || Date.current),
      next_payment_on: new_next
    )

    redirect_to memberships_path(q: client.id),
      notice: "Pago registrado (#{plan.humanize}) por $#{(amount_cents / 100.0).round(2)}. Próximo pago: #{new_next}."
  rescue ActiveRecord::RecordNotFound
    redirect_to memberships_path, alert: "Cliente no encontrado."
  rescue => e
    redirect_to memberships_path(q: params[:q]), alert: "No se pudo completar el cobro: #{e.message}"
  end

  private

  # Busca por #ID exacto o por nombre (primer match)
  def lookup_client(q)
    if q.to_i.to_s == q
      Client.find_by(id: q.to_i)
    else
      Client.where("LOWER(name) LIKE ?", "%#{q.downcase}%").first
    end
  end
end

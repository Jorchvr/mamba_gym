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

    # Ventas de tienda (StoreSale), incluyendo las de Griselle
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
    @count        = @transactions.size
    @total_cents  = @transactions.sum { |h| h[:amount_cents] }
    @selected_user = user_scope_id ? User.find_by(id: user_scope_id) : nil
  end

  def show
    # ...
  end

  private

  def superuser?
    current_user.respond_to?(:superuser?) ? current_user.superuser? : false
  end
end

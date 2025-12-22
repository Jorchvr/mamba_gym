require "csv"
require "caxlsx"

class ReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_two_factor!, if: -> { respond_to?(:require_two_factor!) }
  before_action :require_superuser!, only: [ :daily_export, :history, :daily_export_excel ]

  # ==========================
  # HISTORIAL (BLINDADO)
  # ==========================
  def history
    @date  = params[:date].present? ? (Date.parse(params[:date]) rescue Time.zone.today) : Time.zone.today
    @range = params[:range].presence&.to_sym
    @range = :day unless %i[day week month year].include?(@range)

    from, to = date_range_for(@date, @range)

    @sales = Sale.where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to)
                 .includes(:user, :client).order(created_at: :desc)

    @store_sales = StoreSale.where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", from, to)
                            .includes(:user, store_sale_items: :product).order(created_at: :desc)

    @expenses = Expense.where("occurred_at BETWEEN ? AND ?", from, to)
                       .includes(:user).order(occurred_at: :desc)

    @check_ins = CheckIn.where("COALESCE(check_ins.occurred_at, check_ins.created_at) BETWEEN ? AND ?", from, to)
                        .includes(:client, :user)

    @new_clients = Client.where(created_at: from..to).includes(:user)

    @inventory_events = if defined?(InventoryEvent)
                          InventoryEvent.where(happened_at: from..to).includes(:product, :user).order(:happened_at)
    else
                          []
    end

    # Cálculos seguros (.to_i evita errores de nil)
    sales_cents = @sales.sum(:amount_cents).to_i
    store_cents = @store_sales.sum(:total_cents).to_i
    gross_income = sales_cents + store_cents

    expenses_cents = @expenses.sum(:amount_cents).to_i

    # Total Neto
    @money_total_cents = gross_income - expenses_cents

    # Desglose efectivo vs transferencia
    cash_sales = @sales.where(payment_method: :cash).sum(:amount_cents).to_i
    cash_store = @store_sales.where(payment_method: :cash).sum(:total_cents).to_i
    cash_net   = (cash_sales + cash_store) - expenses_cents

    transfer_sales = @sales.where(payment_method: :transfer).sum(:amount_cents).to_i
    transfer_store = @store_sales.where(payment_method: :transfer).sum(:total_cents).to_i

    @money_by_method = {
      "cash"     => cash_net,
      "transfer" => transfer_sales + transfer_store
    }

    # Productos visuales
    items_all = @store_sales.flat_map { |ss| ss.store_sale_items.to_a }
    @sold_by_product = items_all.group_by(&:product_id).map do |pid, arr|
      product = arr.first&.product
      {
        product_name: product&.name || "Producto ##{pid}",
        sold_qty: arr.sum { |it| it.quantity.to_i },
        revenue_cents: arr.sum { |it| it.unit_price_cents.to_i * it.quantity.to_i },
        remaining_stock: product&.stock.to_i
      }
    end.sort_by { |h| -h[:sold_qty] }
  end

  # ==========================
  # CORTE DEL DÍA (TICKET)
  # ==========================
  def closeout
    date = Time.zone.today
    from, to = date_range_for(date, :day)

    # 1. Consultas (solo usuario actual)
    sales = Sale.where(user_id: current_user.id)
                .where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to)
                .includes(:client)

    store_sales = StoreSale.where(user_id: current_user.id)
                           .where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", from, to)
                           .includes(:user, store_sale_items: :product)

    expenses = Expense.where(user_id: current_user.id)
                      .where("occurred_at BETWEEN ? AND ?", from, to)

    # 2. Cálculos para el Ticket (Separando Ingresos de Ajustes)
    # Ingresos (Positivos)
    @member_cents = sales.where("amount_cents >= 0").sum(:amount_cents).to_i
    @store_cents  = store_sales.where("total_cents >= 0").sum(:total_cents).to_i

    # Ajustes (Negativos)
    neg_sales = sales.where("amount_cents < 0").sum(:amount_cents).to_i
    neg_store = store_sales.where("total_cents < 0").sum(:total_cents).to_i
    @adjustments_cents = neg_sales + neg_store

    # Gastos
    @expenses_cents = expenses.sum(:amount_cents).to_i

    # Total Final
    @total_cents = (@member_cents + @store_cents + @adjustments_cents) - @expenses_cents
    @ops_count   = sales.count + store_sales.count + expenses.count

    # Métodos de Pago
    cash_in = sales.where(payment_method: :cash).sum(:amount_cents).to_i +
              store_sales.where(payment_method: :cash).sum(:total_cents).to_i

    transfer_in = sales.where(payment_method: :transfer).sum(:amount_cents).to_i +
                  store_sales.where(payment_method: :transfer).sum(:total_cents).to_i

    @by_method = {
      "cash"     => cash_in - @expenses_cents,
      "transfer" => transfer_in
    }

    @user_name = current_user.name.presence || current_user.email
    @date      = date
    @new_clients_today = Client.where(created_at: from..to).count
    @checkins_today    = CheckIn.where("COALESCE(check_ins.occurred_at, check_ins.created_at) BETWEEN ? AND ?", from, to).count

    # 3. Transacciones Detalladas
    @transactions = []
    sales.each do |s|
      @transactions << { at: (s.occurred_at || s.created_at), label: "Membresía #{s.membership_type}", amount_cents: s.amount_cents.to_i }
    end
    store_sales.each do |ss|
      @transactions << { at: (ss.occurred_at || ss.created_at), label: "Tienda ##{ss.id}", amount_cents: ss.total_cents.to_i }
    end
    expenses.each do |ex|
      @transactions << { at: ex.occurred_at, label: "GASTO: #{ex.description}", amount_cents: -ex.amount_cents.to_i }
    end
    @transactions.sort_by! { |h| h[:at] }

    # 4. Detalle Productos
    items = store_sales.flat_map { |ss| ss.store_sale_items.to_a }
    @sold_by_product = items.group_by(&:product_id).map do |pid, arr|
      product = arr.first&.product
      {
        product_name: product&.name || "Producto ##{pid}",
        sold_qty: arr.sum { |it| it.quantity.to_i },
        revenue_cents: arr.sum { |it| it.unit_price_cents.to_i * it.quantity.to_i },
        stock_after: product&.stock.to_i
      }
    end
  end

  # ==========================
  # EXPORTACIONES
  # ==========================
  def daily_export
    day = Time.zone.today
    from, to = date_range_for(day, :day)
    filename = "reporte_#{day.strftime('%Y-%m-%d')}.csv"
    send_data "CSV no configurado.", filename: filename
  end

  def daily_export_excel
    head :ok
  end

  private

  def date_range_for(date, range)
    case range
    when :day  then [ date.beginning_of_day,  date.end_of_day ]
    when :week then [ date.beginning_of_week, date.end_of_week ]
    when :month then [ date.beginning_of_month, date.end_of_month ]
    when :year  then [ date.beginning_of_year, date.end_of_year ]
    else            [ date.beginning_of_day,  date.end_of_day ]
    end
  end
end

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

    @sales = Sale.where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to).includes(:user, :client).order(created_at: :desc)
    @store_sales = StoreSale.where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", from, to).includes(:user, store_sale_items: :product).order(created_at: :desc)
    @expenses = Expense.where("occurred_at BETWEEN ? AND ?", from, to).includes(:user).order(occurred_at: :desc)
    @check_ins = CheckIn.where("COALESCE(check_ins.occurred_at, check_ins.created_at) BETWEEN ? AND ?", from, to).includes(:client, :user)
    @new_clients = Client.where(created_at: from..to).includes(:user)

    # CÁLCULOS SEGUROS
    sales_cents = @sales.sum(:amount_cents).to_i

    # FIX: Calcular tienda sumando items, no encabezados (para evitar errores de sincronización)
    store_items = @store_sales.flat_map(&:store_sale_items)
    store_cents = store_items.sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }

    gross_income = sales_cents + store_cents
    expenses_cents = @expenses.sum(:amount_cents).to_i
    @money_total_cents = gross_income - expenses_cents

    cash_sales = @sales.where(payment_method: :cash).sum(:amount_cents).to_i
    # Calcular efectivo de tienda basado en items reales
    cash_store_sales = @store_sales.select { |s| s.payment_method == "cash" }
    cash_store_items = cash_store_sales.flat_map(&:store_sale_items)
    cash_store = cash_store_items.sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }

    cash_net   = (cash_sales + cash_store) - expenses_cents

    # Transferencia
    transfer_sales = @sales.where(payment_method: :transfer).sum(:amount_cents).to_i
    transfer_net = (sales_cents + store_cents) - (cash_sales + cash_store) # Lo que sobra es transfer

    @money_by_method = { "cash" => cash_net, "transfer" => transfer_net }

    @sold_by_product = store_items.group_by(&:product_id).map do |pid, arr|
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
  # CORTE DEL DÍA (TICKET) - FIX MATEMÁTICO 100%
  # ==========================
  def closeout
    date = Time.zone.today
    from, to = date_range_for(date, :day)

    # 1. Consultas
    sales = Sale.where(user_id: current_user.id)
                .where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to)
                .includes(:client)

    store_sales = StoreSale.where(user_id: current_user.id)
                           .where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", from, to)
                           .includes(:user, store_sale_items: :product)

    expenses = Expense.where(user_id: current_user.id)
                      .where("occurred_at BETWEEN ? AND ?", from, to)

    # 2. CÁLCULOS BASADOS EN ITEMS (Esto arregla tu error de $68)
    # En lugar de sumar el total de la venta, sumamos los productos uno por uno.

    # A) Ingresos Membresía
    @member_cents = sales.where("amount_cents >= 0").sum(:amount_cents).to_i
    neg_member_cents = sales.where("amount_cents < 0").sum(:amount_cents).to_i

    # B) Ingresos Tienda (Calculado desde ITEMS)
    all_store_items = store_sales.flat_map { |ss| ss.store_sale_items }

    # Separamos items positivos (ventas) de negativos (devoluciones)
    @store_cents = all_store_items.select { |i| i.unit_price_cents.to_i >= 0 }
                                  .sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }

    neg_store_cents = all_store_items.select { |i| i.unit_price_cents.to_i < 0 }
                                     .sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }

    # C) Ajustes y Gastos
    @adjustments_cents = neg_member_cents + neg_store_cents
    @expenses_cents = expenses.sum(:amount_cents).to_i

    # D) TOTAL FINAL EXACTO
    @total_cents = (@member_cents + @store_cents + @adjustments_cents) - @expenses_cents
    @ops_count   = sales.count + store_sales.count + expenses.count

    # E) Desglose Métodos de Pago
    # Efectivo Membresía
    cash_mem = sales.where(payment_method: :cash).sum(:amount_cents).to_i
    # Efectivo Tienda (Desde items)
    cash_store_sales = store_sales.select { |s| s.payment_method == "cash" }
    cash_store_items = cash_store_sales.flat_map(&:store_sale_items)
    cash_store = cash_store_items.sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }

    total_cash_gross = cash_mem + cash_store

    # Transferencias (El resto)
    total_transfer = (@member_cents + @store_cents + @adjustments_cents) - total_cash_gross

    @by_method = {
      "cash"     => total_cash_gross - @expenses_cents, # Restamos gastos al efectivo
      "transfer" => total_transfer
    }

    @user_name = current_user.name.presence || current_user.email
    @date      = date
    @new_clients_today = Client.where(created_at: from..to).count
    @checkins_today    = CheckIn.where("COALESCE(check_ins.occurred_at, check_ins.created_at) BETWEEN ? AND ?", from, to).count

    # 3. Datos visuales
    @sold_by_product = all_store_items.group_by(&:product_id).map do |pid, arr|
      product = arr.first&.product
      {
        product_name: product&.name || "Producto ##{pid}",
        sold_qty: arr.sum { |it| it.quantity.to_i },
        revenue_cents: arr.sum { |it| it.unit_price_cents.to_i * it.quantity.to_i },
        stock_after: product&.stock.to_i
      }
    end.sort_by { |h| -h[:sold_qty] }
  end

  def daily_export; head :ok; end
  def daily_export_excel; head :ok; end

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

require "csv"
require "caxlsx"

class ReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_two_factor!, if: -> { respond_to?(:require_two_factor!) }
  before_action :require_superuser!, only: [ :daily_export, :history, :daily_export_excel ]

  # ==========================
  # HISTORIAL
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

    # Cálculos
    sales_cents = @sales.sum(:amount_cents).to_i
    store_items = @store_sales.flat_map(&:store_sale_items)
    store_cents = store_items.sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }

    gross_income = sales_cents + store_cents
    expenses_cents = @expenses.sum(:amount_cents).to_i
    @money_total_cents = gross_income - expenses_cents

    # Métodos de pago
    cash_sales = @sales.where(payment_method: :cash).sum(:amount_cents).to_i
    cash_store_sales = @store_sales.select { |s| s.payment_method == "cash" }
    cash_store_items = cash_store_sales.flat_map(&:store_sale_items)
    cash_store = cash_store_items.sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }
    cash_net   = (cash_sales + cash_store) - expenses_cents

    transfer_sales = @sales.where(payment_method: :transfer).sum(:amount_cents).to_i
    transfer_net = (sales_cents + store_cents) - (cash_sales + cash_store)

    @money_by_method = { "cash" => cash_net, "transfer" => transfer_net }

    # === MODIFICADO: Agrupación para ver nombres personalizados ===
    @sold_by_product = store_items.group_by { |i| i.product_id || "custom-#{i.name}" }.map do |key, arr|
      first_item = arr.first
      product = first_item.product

      # PRIORIDAD: Nombre del item guardado > Nombre del producto > Fallback
      display_name = first_item.name.presence || product&.name || "Producto ##{key}"

      {
        product_name: display_name,
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

    # 1. Consultas
    sales = Sale.where(user_id: current_user.id)
                .where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to)
                .includes(:client)

    store_sales = StoreSale.where(user_id: current_user.id)
                           .where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", from, to)
                           .includes(:user, store_sale_items: :product)

    expenses = Expense.where(user_id: current_user.id)
                      .where("occurred_at BETWEEN ? AND ?", from, to)

    # 2. CÁLCULOS
    @member_cents = sales.where("amount_cents >= 0").sum(:amount_cents).to_i
    neg_member_cents = sales.where("amount_cents < 0").sum(:amount_cents).to_i

    all_store_items = store_sales.flat_map { |ss| ss.store_sale_items }

    @store_cents = all_store_items.select { |i| i.unit_price_cents.to_i >= 0 }
                                  .sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }

    neg_store_cents = all_store_items.select { |i| i.unit_price_cents.to_i < 0 }
                                     .sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }

    @adjustments_cents = neg_member_cents + neg_store_cents
    @expenses_cents = expenses.sum(:amount_cents).to_i

    @total_cents = (@member_cents + @store_cents + @adjustments_cents) - @expenses_cents
    @ops_count   = sales.count + store_sales.count + expenses.count

    cash_mem = sales.where(payment_method: :cash).sum(:amount_cents).to_i

    cash_store_sales = store_sales.select { |s| s.payment_method == "cash" }
    cash_store_items = cash_store_sales.flat_map(&:store_sale_items)
    cash_store = cash_store_items.sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }

    total_cash_gross = cash_mem + cash_store
    total_transfer = (@member_cents + @store_cents + @adjustments_cents) - total_cash_gross

    @by_method = {
      "cash"     => total_cash_gross - @expenses_cents,
      "transfer" => total_transfer
    }

    @user_name = current_user.name.presence || current_user.email
    @date      = date
    @new_clients_today = Client.where(created_at: from..to).count
    @checkins_today    = CheckIn.where("COALESCE(check_ins.occurred_at, check_ins.created_at) BETWEEN ? AND ?", from, to).count

    # === MODIFICADO: Agrupación para ver nombres personalizados en el corte ===
    @sold_by_product = all_store_items.group_by { |i| i.product_id || "custom-#{i.name}" }.map do |key, arr|
      first_item = arr.first
      product = first_item.product
      display_name = first_item.name.presence || product&.name || "Producto ##{key}"

      {
        product_name: display_name,
        sold_qty: arr.sum { |it| it.quantity.to_i },
        revenue_cents: arr.sum { |it| it.unit_price_cents.to_i * it.quantity.to_i },
        stock_after: product&.stock.to_i
      }
    end.sort_by { |h| -h[:sold_qty] }

    @transactions = []
    sales.each do |s|
      @transactions << {
        at: (s.occurred_at || s.created_at),
        label: "Membresía #{s.membership_type}",
        amount_cents: s.amount_cents.to_i
      }
    end
    store_sales.each do |ss|
      real_total = ss.store_sale_items.sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }

      # === MODIFICADO: Mostrar nombres de items (Griselle) en lugar de Tienda #ID ===
      item_names = ss.store_sale_items.map { |i| i.name.presence || i.product&.name || "Item" }.join(", ")
      label_text = item_names.present? ? item_names.truncate(30) : "Tienda ##{ss.id}"

      @transactions << {
        at: (ss.occurred_at || ss.created_at),
        label: label_text,
        amount_cents: real_total
      }
    end
    expenses.each do |ex|
      @transactions << {
        at: ex.occurred_at,
        label: "GASTO: #{ex.description}",
        amount_cents: -ex.amount_cents.to_i
      }
    end
    @transactions.sort_by! { |h| h[:at] }
  end

  def daily_export; head :ok; end

  # ==========================
  # EXCEL DEL DÍA (AGREGADO)
  # ==========================
  def daily_export_excel
    target_date = params[:date].present? ? (Date.parse(params[:date]) rescue Time.zone.today) : Time.zone.today
    from = target_date.beginning_of_day
    to   = target_date.end_of_day

    sales = Sale.where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to).includes(:user, :client)
    store_sales = StoreSale.where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", from, to).includes(:user, store_sale_items: :product)
    expenses = Expense.where("occurred_at BETWEEN ? AND ?", from, to).includes(:user)

    p = Axlsx::Package.new
    wb = p.workbook

    styles = wb.styles
    header_style = styles.add_style(bg_color: "D4AF37", fg_color: "000000", b: true, alignment: { horizontal: :center })
    title_style  = styles.add_style(b: true, sz: 14)
    currency     = styles.add_style(format_code: "$#,##0.00")
    bold         = styles.add_style(b: true)

    wb.add_worksheet(name: "Reporte #{target_date}") do |sheet|
      sheet.add_row [ "REPORTE DEL DÍA", target_date.strftime("%d/%m/%Y") ], style: title_style
      sheet.add_row []

      total_membresias = sales.sum(:amount_cents)
      all_items = store_sales.flat_map(&:store_sale_items)
      total_tienda = all_items.sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }
      total_gastos = expenses.sum(:amount_cents)
      total_neto = (total_membresias + total_tienda) - total_gastos

      # --- RESUMEN ---
      sheet.add_row [ "RESUMEN FINANCIERO" ], style: bold
      sheet.add_row [ "Ingresos Membresías", total_membresias / 100.0 ], style: [ nil, currency ]
      sheet.add_row [ "Ingresos Tienda / Ventas Externas", total_tienda / 100.0 ], style: [ nil, currency ]
      sheet.add_row [ "(-) Gastos Operativos", total_gastos / 100.0 ], style: [ nil, currency ]
      sheet.add_row [ "TOTAL NETO", total_neto / 100.0 ], style: [ bold, currency ]
      sheet.add_row []
      sheet.add_row []

      # --- SECCIÓN 1: MEMBRESÍAS ---
      sheet.add_row [ "SECCIÓN 1: MEMBRESÍAS" ], style: title_style
      sheet.add_row [ "Hora", "Cliente", "Concepto/Plan", "Usuario", "Método", "Monto" ], style: header_style

      if sales.any?
        sales.each do |s|
          sheet.add_row [
            (s.occurred_at || s.created_at).strftime("%H:%M"),
            s.client&.name || "Eliminado",
            s.membership_type&.humanize,
            s.user&.name || s.user&.email,
            translate_method(s.payment_method),
            s.amount_cents / 100.0
          ], style: [ nil, nil, nil, nil, nil, currency ]
        end
      else
        sheet.add_row [ "Sin movimientos de membresía" ]
      end
      sheet.add_row []

      # --- SECCIÓN 2: TIENDA / GRISELLE ---
      sheet.add_row [ "SECCIÓN 2: VENTAS TIENDA / CLASES" ], style: title_style
      sheet.add_row [ "Hora", "Descripción / Producto", "Cant.", "P. Unitario", "Subtotal", "Usuario", "Método" ], style: header_style

      if store_sales.any?
        store_sales.each do |ss|
          ss.store_sale_items.each do |item|
            subtotal = (item.unit_price_cents.to_i * item.quantity.to_i) / 100.0

            # Nombre correcto del servicio/producto para el Excel
            item_name = item.name.presence || item.product&.name || "Desconocido"

            sheet.add_row [
              (ss.occurred_at || ss.created_at).strftime("%H:%M"),
              item_name,
              item.quantity,
              item.unit_price_cents / 100.0,
              subtotal,
              ss.user&.name || ss.user&.email,
              translate_method(ss.payment_method)
            ], style: [ nil, nil, nil, currency, currency, nil, nil ]
          end
        end
      else
        sheet.add_row [ "Sin ventas de tienda" ]
      end
      sheet.add_row []

      # --- SECCIÓN 3: GASTOS ---
      sheet.add_row [ "SECCIÓN 3: GASTOS" ], style: title_style
      sheet.add_row [ "Hora", "Descripción", "Responsable", "Monto" ], style: header_style

      if expenses.any?
        expenses.each do |ex|
          sheet.add_row [
            ex.occurred_at.strftime("%H:%M"),
            ex.description,
            ex.user&.name || ex.user&.email,
            ex.amount_cents / 100.0
          ], style: [ nil, nil, nil, currency ]
        end
      else
        sheet.add_row [ "Sin gastos registrados" ]
      end
    end

    send_data p.to_stream.read, filename: "Reporte_#{target_date.strftime('%Y%m%d')}.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  private

  def translate_method(method)
    case method.to_s
    when "cash" then "Efectivo"
    when "transfer" then "Transferencia"
    when "card" then "Tarjeta"
    else method
    end
  end

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

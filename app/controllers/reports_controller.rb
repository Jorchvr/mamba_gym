# app/controllers/reports_controller.rb
require "csv"
require "caxlsx"

class ReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_two_factor!, if: -> { respond_to?(:require_two_factor!) }
  # Solo superusuario puede ver historial y exportar (CSV/XLSX); el corte lo ve cualquier usuario autenticado
  before_action :require_superuser!, only: [:daily_export, :history, :daily_export_excel]

  # ==========================
  # DESCARGA CSV DEL DÍA (solo superusuario)
  # ==========================
  def daily_export
    day = Time.zone.today
    from, to = date_range_for(day, :day)
    filename = "reporte_#{day.strftime('%Y-%m-%d')}.csv"

    # Calificar columnas en COALESCE para evitar ambigüedad
    store_sales  = StoreSale.where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", from, to)
                            .includes(:user)
    member_sales = Sale.where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to)
                       .includes(:user, :client)
    check_ins    = CheckIn.where("COALESCE(check_ins.occurred_at, check_ins.created_at) BETWEEN ? AND ?", from, to)
                          .includes(:client)

    total_cents = store_sales.sum(:total_cents).to_i + member_sales.sum(:amount_cents).to_i

    csv_str = CSV.generate(col_sep: ",") do |csv|
      # Portada
      csv << [ "Reporte Diario", day.to_s ]
      csv << [ "Generado por", current_user.name ]
      csv << []
      csv << [ "Resumen" ]
      csv << [ "Total operaciones (tienda + membresías)", (store_sales.size + member_sales.size) ]
      csv << [ "Total vendido (MXN)", (total_cents / 100.0).round(2) ]
      csv << []

      # Ventas de tienda
      csv << [ "Ventas de Tienda (StoreSale)" ]
      csv << [ "ID", "Fecha/Hora", "Usuario", "Método pago", "Total (MXN)" ]
      store_sales.each do |s|
        ts = (s.occurred_at || s.created_at)&.in_time_zone&.strftime("%Y-%m-%d %H:%M")
        csv << [ s.id, ts, s.user&.name, s.payment_method, (s.total_cents.to_i / 100.0).round(2) ]
      end
      csv << []

      # Items por venta (tienda)
      store_sales.includes(store_sale_items: :product).each do |s|
        next if s.store_sale_items.blank?
        csv << [ "Items de la venta ##{s.id}" ]
        csv << [ "Producto", "Cantidad", "P.U. (MXN)", "Subtotal (MXN)" ]
        s.store_sale_items.each do |it|
          csv << [
            it.product&.name,
            it.quantity,
            (it.unit_price_cents.to_i / 100.0).round(2),
            ((it.unit_price_cents.to_i * it.quantity) / 100.0).round(2)
          ]
        end
        csv << []
      end

      # Ventas de membresías
      if member_sales.present?
        csv << [ "Ventas de Membresías (Sale)" ]
        csv << [ "ID", "Fecha/Hora", "Usuario", "Cliente", "Membresía", "Monto (MXN)", "Método pago" ]
        member_sales.each do |s|
          ts = (s.occurred_at || s.created_at)&.in_time_zone&.strftime("%Y-%m-%d %H:%M")
          client_name = s.try(:client)&.name || s.try(:client_name)
          csv << [
            s.id,
            ts,
            s.user&.name,
            client_name,
            (s.try(:membership_type) || "-"),
            (s.amount_cents.to_i / 100.0).round(2),
            (s.try(:payment_method) || "-")
          ]
        end
        csv << []
      end

      # Entradas (CheckIns)
      if check_ins.present?
        csv << [ "Entradas del día (CheckIn)" ]
        csv << [ "Hora", "Cliente", "ID Cliente" ]
        check_ins.each do |ci|
          hh = (ci.occurred_at || ci.created_at)&.in_time_zone&.strftime("%H:%M")
          csv << [ hh, ci.client&.name, ci.client_id ]
        end
        csv << []
      end
    end

    send_data csv_str, filename: filename, type: "text/csv; charset=utf-8"
  end

  # ==========================
  # EXCEL (2 hojas): Historial del día + Cortes por usuario (solo superusuario)
  # ==========================
  def daily_export_excel
    day = Time.zone.today
    from, to = date_range_for(day, :day)
    filename = "reporte_#{day.strftime('%Y-%m-%d')}.xlsx"

    sales = Sale.where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to)
                .includes(:user, :client)

    store_sales = StoreSale.where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", from, to)
                           .includes(:user, store_sale_items: :product)

    check_ins = CheckIn.where("COALESCE(check_ins.occurred_at, check_ins.created_at) BETWEEN ? AND ?", from, to)
                       .includes(:client, :user)

    new_clients = Client.where(created_at: from..to).includes(:user)

    total_cents = sales.sum(:amount_cents).to_i + store_sales.sum(:total_cents).to_i

    # Desglose por método (día)
    day_cash_cents     = sales.where(payment_method: :cash).sum(:amount_cents).to_i +
                         store_sales.where(payment_method: :cash).sum(:total_cents).to_i
    day_transfer_cents = sales.where(payment_method: :transfer).sum(:amount_cents).to_i +
                         store_sales.where(payment_method: :transfer).sum(:total_cents).to_i

    # Productos vendidos (día)
    items_all = store_sales.flat_map { |ss| ss.store_sale_items.to_a }
    grouped_items = items_all.group_by(&:product_id)
    sold_by_product = grouped_items.map do |product_id, arr|
      product = arr.first&.product
      qty   = arr.sum { |it| it.quantity.to_i }
      rev_c = arr.sum { |it| it.unit_price_cents.to_i * it.quantity.to_i }
      {
        product_name: (product&.name.presence || "Producto ##{product_id} (eliminado)"),
        qty: qty,
        revenue_cents: rev_c,
        remaining_stock: product&.stock.to_i
      }
    end
    sold_by_product.sort_by! { |h| -h[:qty].to_i }

    # Cortes por usuario
    user_stats = {}
    user_sales = Hash.new { |h, k| h[k] = [] } # ventas de membresía por user_id
    user_ss    = Hash.new { |h, k| h[k] = [] } # ventas de tienda por user_id

    sales.each do |s|
      uid = s.user_id
      next unless uid
      user_stats[uid] ||= { user: s.user, ops: 0, total: 0, cash: 0, transfer: 0, mem: 0, store: 0, checkins: 0, new_clients: 0 }
      st = user_stats[uid]
      st[:ops]   += 1
      st[:total] += s.amount_cents.to_i
      st[:mem]   += s.amount_cents.to_i
      if s.payment_method.to_s == "cash" || s.payment_method.to_i == 0
        st[:cash] += s.amount_cents.to_i
      else
        st[:transfer] += s.amount_cents.to_i
      end
      user_sales[uid] << s
    end

    store_sales.each do |ss|
      uid = ss.user_id
      next unless uid
      user_stats[uid] ||= { user: ss.user, ops: 0, total: 0, cash: 0, transfer: 0, mem: 0, store: 0, checkins: 0, new_clients: 0 }
      st = user_stats[uid]
      st[:ops]   += 1
      st[:total] += ss.total_cents.to_i
      st[:store] += ss.total_cents.to_i
      if ss.payment_method.to_s == "cash" || ss.payment_method.to_i == 0
        st[:cash] += ss.total_cents.to_i
      else
        st[:transfer] += ss.total_cents.to_i
      end
      user_ss[uid] << ss
    end

    check_ins.each do |ci|
      uid = ci.user_id
      next unless uid
      user_stats[uid] ||= { user: ci.user, ops: 0, total: 0, cash: 0, transfer: 0, mem: 0, store: 0, checkins: 0, new_clients: 0 }
      user_stats[uid][:checkins] += 1
    end

    new_clients.each do |c|
      uid = c.user_id
      next unless uid
      user_stats[uid] ||= { user: c.user, ops: 0, total: 0, cash: 0, transfer: 0, mem: 0, store: 0, checkins: 0, new_clients: 0 }
      user_stats[uid][:new_clients] += 1
    end

    # ===== Excel =====
    pkg = Axlsx::Package.new
    wb  = pkg.workbook

    currency_fmt = wb.styles.add_style(num_fmt: 4) # 0.00
    header_style = wb.styles.add_style(b: true, alignment: { horizontal: :center })
    bold_style   = wb.styles.add_style(b: true)

    # ---------- Hoja 1: Historial del día ----------
    wb.add_worksheet(name: "Historial (día actual)") do |ws|
      ws.add_row ["Reporte Diario (#{day})"], style: [bold_style]
      ws.add_row ["Total operaciones (tienda + membresías)", (sales.size + store_sales.size)]
      ws.add_row ["Total vendido (MXN)", (total_cents / 100.0)], style: [nil, currency_fmt]
      ws.add_row ["Efectivo (MXN)", (day_cash_cents / 100.0)], style: [nil, currency_fmt]
      ws.add_row ["Transferencia (MXN)", (day_transfer_cents / 100.0)], style: [nil, currency_fmt]
      ws.add_row []

      # Ventas Tienda (StoreSale)
      ws.add_row ["Ventas de Tienda (StoreSale)"], style: [bold_style]
      ws.add_row ["ID", "Fecha/Hora", "Usuario", "Método pago", "Total (MXN)"], style: [header_style]*5
      store_sales.each do |s|
        ts = (s.occurred_at || s.created_at)&.in_time_zone&.strftime("%Y-%m-%d %H:%M")
        ws.add_row [s.id, ts, (s.user&.name || s.user&.email), s.payment_method, (s.total_cents.to_i/100.0)],
                   style: [nil, nil, nil, nil, currency_fmt]
      end
      ws.add_row []

      # Items por venta (tienda)
      store_sales.each do |s|
        next if s.store_sale_items.blank?
        ws.add_row ["Items de la venta ##{s.id}"], style: [bold_style]
        ws.add_row ["Producto", "Cantidad", "P.U. (MXN)", "Subtotal (MXN)"], style: [header_style]*4
        s.store_sale_items.each do |it|
          ws.add_row [
            it.product&.name,
            it.quantity,
            (it.unit_price_cents.to_i / 100.0),
            ((it.unit_price_cents.to_i * it.quantity) / 100.0)
          ], style: [nil, nil, currency_fmt, currency_fmt]
        end
        ws.add_row []
      end

      # Ventas de Membresías
      if sales.present?
        ws.add_row ["Ventas de Membresías (Sale)"], style: [bold_style]
        ws.add_row ["ID", "Fecha/Hora", "Usuario", "Cliente", "Membresía", "Monto (MXN)", "Método pago"], style: [header_style]*7
        sales.each do |s|
          ts = (s.occurred_at || s.created_at)&.in_time_zone&.strftime("%Y-%m-%d %H:%M")
          client_name = s.client&.name
          ws.add_row [
            s.id, ts, (s.user&.name || s.user&.email), client_name,
            (s.membership_type || "-"),
            (s.amount_cents.to_i/100.0),
            (s.payment_method || "-")
          ], style: [nil, nil, nil, nil, nil, currency_fmt, nil]
        end
        ws.add_row []
      end

      # Check-ins
      if check_ins.present?
        ws.add_row ["Entradas del día (CheckIn)"], style: [bold_style]
        ws.add_row ["Hora", "Cliente", "Usuario"], style: [header_style]*3
        check_ins.each do |ci|
          hh = (ci.occurred_at || ci.created_at)&.in_time_zone&.strftime("%H:%M")
          ws.add_row [hh, ci.client&.name, (ci.user&.name || ci.user&.email)]
        end
        ws.add_row []
      end

      # Nuevos clientes
      if new_clients.present?
        ws.add_row ["Nuevos clientes"], style: [bold_style]
        ws.add_row ["Hora", "Cliente", "Usuario"], style: [header_style]*3
        new_clients.each do |c|
          hh = c.created_at&.in_time_zone&.strftime("%H:%M")
          ws.add_row [hh, c.name, (c.user&.name || c.user&.email)]
        end
        ws.add_row []
      end

      # Productos vendidos (día)
      ws.add_row ["Productos vendidos (día)"], style: [bold_style]
      ws.add_row ["Producto", "Cantidad vendida", "Ingreso (MXN)", "Stock restante"], style: [header_style]*4
      if sold_by_product.blank?
        ws.add_row ["Sin ventas de tienda", nil, nil, nil]
      else
        sold_by_product.each do |r|
          ws.add_row [
            r[:product_name],
            r[:qty],
            (r[:revenue_cents].to_i / 100.0),
            r[:remaining_stock].to_i
          ], style: [nil, nil, currency_fmt, nil]
        end
      end

      ws.column_widths 10, 20, 24, 16, 16
    end

    # ---------- Hoja 2: Cortes por usuario ----------
    wb.add_worksheet(name: "Cortes por usuario") do |ws|
      ws.add_row ["Cortes del día #{day}"], style: [bold_style]
      ws.add_row []
      ws.add_row ["Usuario", "Operaciones", "Total (MXN)", "Efectivo (MXN)", "Transferencia (MXN)", "Membresías (MXN)", "Tienda (MXN)", "Check-ins", "Nuevos clientes"], style: [header_style]*9

      # Resumen por usuario
      user_stats.values.sort_by { |h| -(h[:total] || 0) }.each do |st|
        u = st[:user]
        uname = (u&.name || u&.email || "Usuario ##{u&.id || '-'}")
        ws.add_row [
          uname, st[:ops],
          (st[:total].to_i/100.0),
          (st[:cash].to_i/100.0),
          (st[:transfer].to_i/100.0),
          (st[:mem].to_i/100.0),
          (st[:store].to_i/100.0),
          st[:checkins].to_i,
          st[:new_clients].to_i
        ], style: [nil, nil, currency_fmt, currency_fmt, currency_fmt, currency_fmt, currency_fmt, nil, nil]
      end

      ws.add_row []
      ws.add_row ["Detalle por usuario"], style: [bold_style]
      ws.add_row []

      # Detalle por usuario
      user_stats.keys.sort.each do |uid|
        st = user_stats[uid]
        u  = st[:user]
        uname = (u&.name || u&.email || "Usuario ##{u&.id || '-'}")

        ws.add_row ["Usuario: #{uname}"], style: [bold_style]
        ws.add_row ["Ventas de Membresías"], style: [bold_style]
        ws.add_row ["ID", "Fecha/Hora", "Cliente", "Membresía", "Monto (MXN)", "Método pago"], style: [header_style]*6

        if user_sales[uid].blank?
          ws.add_row ["Sin ventas de membresías", nil, nil, nil, nil, nil]
        else
          user_sales[uid].each do |s|
            ts = (s.occurred_at || s.created_at)&.in_time_zone&.strftime("%Y-%m-%d %H:%M")
            ws.add_row [
              s.id, ts, (s.client&.name || "-"),
              (s.membership_type || "-"),
              (s.amount_cents.to_i/100.0),
              (s.payment_method || "-")
            ], style: [nil, nil, nil, nil, currency_fmt, nil]
          end
        end

        ws.add_row []
        ws.add_row ["Ventas de Tienda"], style: [bold_style]
        ws.add_row ["ID", "Fecha/Hora", "Método pago", "Total (MXN)"], style: [header_style]*4

        if user_ss[uid].blank?
          ws.add_row ["Sin ventas de tienda", nil, nil, nil]
        else
          user_ss[uid].each do |ss|
            ts = (ss.occurred_at || ss.created_at)&.in_time_zone&.strftime("%Y-%m-%d %H:%M")
            ws.add_row [ss.id, ts, ss.payment_method, (ss.total_cents.to_i/100.0)],
                       style: [nil, nil, nil, currency_fmt]

            # Items de esa venta
            if ss.store_sale_items.any?
              ws.add_row ["Items de la venta ##{ss.id}"], style: [bold_style]
              ws.add_row ["Producto", "Cantidad", "P.U. (MXN)", "Subtotal (MXN)"], style: [header_style]*4
              ss.store_sale_items.each do |it|
                ws.add_row [
                  it.product&.name,
                  it.quantity,
                  (it.unit_price_cents.to_i / 100.0),
                  ((it.unit_price_cents.to_i * it.quantity) / 100.0)
                ], style: [nil, nil, currency_fmt, currency_fmt]
              end
            end

            ws.add_row [] # espacio entre ventas
          end
        end

        ws.add_row [] # espacio entre usuarios
      end

      ws.column_widths 28, 12, 14, 16, 18, 16, 14, 12, 16
    end

    send_data pkg.to_stream.read,
              filename: filename,
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  # ==========================
  # HISTORIAL (solo superusuario)
  # Filtros: ?date=YYYY-MM-DD&range=day|week|month|year
  # ==========================
  def history
    @date  = params[:date].present? ? (Date.parse(params[:date]) rescue Time.zone.today) : Time.zone.today
    @range = params[:range].presence&.to_sym
    @range = :day unless %i[day week month year].include?(@range)

    from, to = date_range_for(@date, @range)

    @sales = Sale.where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to)
                 .includes(:user, :client)

    @store_sales = StoreSale.where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", from, to)
                            .includes(:user, store_sale_items: :product)

    @check_ins = CheckIn.where("COALESCE(check_ins.occurred_at, check_ins.created_at) BETWEEN ? AND ?", from, to)
                        .includes(:client, :user)

    @new_clients  = Client.where(created_at: from..to).includes(:user)

    @inventory_events =
      if defined?(InventoryEvent)
        InventoryEvent.where(happened_at: from..to).includes(:product, :user).order(:happened_at)
      else
        []
      end

    @money_total_cents = @sales.sum(:amount_cents).to_i + @store_sales.sum(:total_cents).to_i
    @money_by_method = {
      "cash"     => @sales.where(payment_method: :cash).sum(:amount_cents).to_i     + @store_sales.where(payment_method: :cash).sum(:total_cents).to_i,
      "transfer" => @sales.where(payment_method: :transfer).sum(:amount_cents).to_i + @store_sales.where(payment_method: :transfer).sum(:total_cents).to_i
    }

    @stock_total_units = Product.sum(:stock).to_i
  end

  # ==========================
  # CORTE (del día actual, por usuario actual)
  # ==========================
  def closeout
    date = Time.zone.today
    from, to = date_range_for(date, :day)

    sales = Sale.where(user_id: current_user.id)
                .where("COALESCE(sales.occurred_at, sales.created_at) BETWEEN ? AND ?", from, to)
                .includes(:client)

    store_sales = StoreSale.where(user_id: current_user.id)
                           .where("COALESCE(store_sales.occurred_at, store_sales.created_at) BETWEEN ? AND ?", from, to)
                           .includes(:user, store_sale_items: :product)

    @ops_count   = sales.count + store_sales.count
    @total_cents = sales.sum(:amount_cents).to_i + store_sales.sum(:total_cents).to_i

    @by_method = {
      "cash"     => sales.where(payment_method: :cash).sum(:amount_cents).to_i +
                    store_sales.where(payment_method: :cash).sum(:total_cents).to_i,
      "transfer" => sales.where(payment_method: :transfer).sum(:amount_cents).to_i +
                    store_sales.where(payment_method: :transfer).sum(:total_cents).to_i
    }

    @user_name = current_user.name.presence || current_user.email
    @date = date

    @new_clients_today = Client.where(created_at: from..to).count
    @checkins_today    = CheckIn.where("COALESCE(check_ins.occurred_at, check_ins.created_at) BETWEEN ? AND ?", from, to).count
    @stock_total_units = Product.sum(:stock).to_i

    # Movimientos del turno (para tabla)
    @transactions = []
    sales.each do |s|
      @transactions << {
        at: (s.occurred_at || s.created_at),
        label: "Membresía #{s.membership_type}",
        amount_cents: s.amount_cents.to_i,
        payment_method: s.payment_method
      }
    end
    store_sales.each do |ss|
      @transactions << {
        at: (ss.occurred_at || ss.created_at),
        label: "Tienda (##{ss.id})",
        amount_cents: ss.total_cents.to_i,
        payment_method: ss.payment_method
      }
    end
    @transactions.sort_by! { |h| h[:at] }

    # Detalle por producto vendido en el turno
    items = store_sales.flat_map { |ss| ss.store_sale_items.to_a }
    grouped = items.group_by(&:product_id)

    @sold_by_product = grouped.map do |product_id, arr|
      product = arr.first&.product
      sold_qty = arr.sum { |it| it.quantity.to_i }
      revenue_cents = arr.sum { |it| it.unit_price_cents.to_i * it.quantity.to_i }
      {
        product: product,
        product_name: (product&.name.presence || "Producto ##{product_id} (eliminado)"),
        sold_qty: sold_qty,
        revenue_cents: revenue_cents,
        remaining_stock: product&.stock.to_i
      }
    end

    @sold_by_product.sort_by! { |h| -h[:sold_qty].to_i }
  end

  private

  def date_range_for(date, range)
    case range
    when :day   then [date.beginning_of_day,  date.end_of_day]
    when :week  then [date.beginning_of_week, date.end_of_week]
    when :month then [date.beginning_of_month, date.end_of_month]
    when :year  then [date.beginning_of_year, date.end_of_year]
    else             [date.beginning_of_day,  date.end_of_day]
    end
  end
end

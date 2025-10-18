require "csv"

class ReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_two_factor!
  before_action :require_superuser!

  def daily_export
    day = Time.zone.today
    filename = "reporte_#{day.strftime('%Y-%m-%d')}.csv"

    # Recopilar datos
    store_sales   = defined?(StoreSale) ? StoreSale.where(occurred_at: day.all_day).includes(:user) : []
    member_sales  = defined?(Sale) ? Sale.where(occurred_at: day.all_day).includes(:user) : []
    check_ins     = defined?(CheckIn) ? CheckIn.where(occurred_at: day.all_day).includes(:client) : []

    total_cents = 0
    total_cents += store_sales.sum(:total_cents).to_i if store_sales.present?
    total_cents += member_sales.sum(:amount_cents).to_i if member_sales.present?

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
        csv << [
          s.id,
          s.occurred_at&.in_time_zone&.strftime("%Y-%m-%d %H:%M"),
          s.user&.name,
          s.payment_method,
          (s.total_cents.to_i / 100.0).round(2)
        ]
      end
      csv << []

      # Items por venta (opcional, secciones extensas)
      store_sales.each do |s|
        csv << [ "Items de la venta ##{s.id}" ]
        csv << [ "Producto", "Cantidad", "P.U. (MXN)", "Subtotal (MXN)" ]
        s.store_sale_items.includes(:product).each do |it|
          csv << [
            it.product&.name,
            it.quantity,
            (it.unit_price_cents.to_i / 100.0).round(2),
            ((it.unit_price_cents.to_i * it.quantity) / 100.0).round(2)
          ]
        end
        csv << []
      end

      # Ventas de membresías (Sale)
      if member_sales.present?
        csv << [ "Ventas de Membresías (Sale)" ]
        csv << [ "ID", "Fecha/Hora", "Usuario", "Cliente", "Membresía", "Monto (MXN)", "Método pago" ]
        member_sales.each do |s|
          client_name = s.try(:client)&.name || s.try(:client_name)
          csv << [
            s.id,
            s.occurred_at&.in_time_zone&.strftime("%Y-%m-%d %H:%M"),
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
          csv << [
            ci.occurred_at&.in_time_zone&.strftime("%H:%M"),
            ci.client&.name,
            ci.client_id
          ]
        end
        csv << []
      end
    end

    send_data csv_str,
              filename: filename,
              type: "text/csv; charset=utf-8"
  end
end

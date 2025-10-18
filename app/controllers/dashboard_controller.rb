class DashboardController < ApplicationController
  before_action :authenticate_user!

  def home
    # ==== Buscador de clientes ====
    @found_client = nil
    if params[:search_number].present?
      q = params[:search_number].to_s.strip
      @found_client =
        if q =~ /\A\d+\z/
          Client.find_by(id: q.to_i)
        else
          Client.where("LOWER(name) LIKE ?", "%#{q.downcase}%").order(:id).first
        end

      # (Opcional) registrar check-in si encontró cliente
      if @found_client.present?
        ensure_check_in!(@found_client)
      end
    end

    # ==== Métrica: personas que han entrado (hoy) ====
    # Usa tu modelo CheckIn si existe; si no, queda en 0
    if defined?(CheckIn)
      @today_checkins = CheckIn.where(occurred_at: Time.zone.today.all_day).count
    else
      @today_checkins = 0
    end

    # ==== Productos para la tienda (panel derecho) ====
    @products = Product.order(:name)

    # ==== Ventas de HOY (todas: tienda + membresías) ====
    @today_sales_count = 0
    @today_total_cents = 0

    # StoreSale (tienda)
    if defined?(StoreSale)
      store_sales_today = StoreSale.where(occurred_at: Time.zone.today.all_day)
      @today_sales_count += store_sales_today.count
      @today_total_cents += store_sales_today.sum(:total_cents).to_i
    end

    # Sale (membresías/inscripciones)
    if defined?(Sale)
      membership_sales_today = Sale.where(occurred_at: Time.zone.today.all_day)
      @today_sales_count += membership_sales_today.count
      @today_total_cents += membership_sales_today.sum(:amount_cents).to_i
    end
  end

  private

  # Marca un check-in del cliente si tienes el modelo CheckIn
  def ensure_check_in!(client)
    return unless defined?(CheckIn)
    # Evita duplicar múltiples check-ins en el mismo día si no quieres
    unless CheckIn.exists?(client_id: client.id, occurred_at: Time.zone.today.all_day)
      CheckIn.create!(client_id: client.id, occurred_at: Time.current)
    end
  rescue => e
    Rails.logger.warn("[CHECKIN] No se pudo registrar check-in: #{e.class} #{e.message}")
  end
end

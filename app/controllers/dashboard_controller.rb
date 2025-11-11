# app/controllers/dashboard_controller.rb
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

      # ✅ Registrar check-in si encontró cliente (una sola vez por día)
      ensure_check_in!(@found_client) if @found_client.present?
    end

    # ==== Métrica: personas que han entrado (hoy) ====
    if defined?(CheckIn)
      @today_checkins = CheckIn.where(occurred_at: Time.zone.today.all_day).count
    else
      @today_checkins = 0
    end

    # ==== Productos para la tienda (panel derecho) ====
    @products = Product.order(:name)

    # ==== Ventas de HOY (solo del usuario actual) ====
    day_range = Time.zone.today.all_day
    @today_sales_count = 0
    @today_total_cents = 0

    if defined?(StoreSale)
      store_sales_today = StoreSale.where(user_id: current_user.id, occurred_at: day_range)
      @today_sales_count += store_sales_today.count
      @today_total_cents += store_sales_today.sum(:total_cents).to_i
    end

    if defined?(Sale)
      membership_sales_today = Sale.where(user_id: current_user.id, occurred_at: day_range)
      @today_sales_count += membership_sales_today.count
      @today_total_cents += membership_sales_today.sum(:amount_cents).to_i
    end
  end

  private

  # Marca un check-in del cliente SOLO una vez por día.
  # Importante: tu tabla check_ins requiere user_id NOT NULL, así que pasamos current_user.
  def ensure_check_in!(client)
    return unless defined?(CheckIn)
    today = Time.zone.today.all_day

    exists = CheckIn.where(client_id: client.id, occurred_at: today).exists?
    return if exists

    CheckIn.create!(
      client_id:   client.id,
      user_id:     current_user.id,
      occurred_at: Time.current
    )
  rescue => e
    Rails.logger.warn("[CHECKIN] No se pudo registrar check-in: #{e.class} #{e.message}")
  end
end

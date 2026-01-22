class ClientsController < ApplicationController
  # 🛡️ SEGURIDAD: Permitimos que el C# entre sin token de autenticidad.
  skip_before_action :verify_authenticity_token, only: [ :check_entry, :fingerprints_data ]
  before_action :authenticate_user!, except: [ :check_entry, :fingerprints_data ]
  before_action :set_client, only: [ :show, :edit, :update, :start_registration, :fingerprint_status, :attach_last_fingerprint, :card_view ]

  # =========================================================
  # 🔌 1. HARDWARE Y SINCRONIZACIÓN C# (CORREGIDO)
  # =========================================================

  def fingerprints_data
    clients = Client.where.not(fingerprint: [ nil, "" ]).select(:id, :fingerprint, :name)
    render json: clients
  end

  def start_scanner
    Thread.new do
      puts ">>> INTENTANDO INICIAR PUENTE C#..."
      project_path = "C:\\Users\\ramoo\\Documents\\PuenteHuella"
      system("cmd.exe /C \"cd #{project_path} && dotnet run\"")
    end
    redirect_back(fallback_location: authenticated_root_path, notice: "🔌 Orden de encendido enviada.")
  end

  def check_entry
    if params[:client_id].present?
      @client = Client.find_by(id: params[:client_id])
      if @client
        begin
          system_user = User.first
          CheckIn.create!(
            client: @client,
            occurred_at: Time.current,
            user: system_user
          )
          puts "✅ ASISTENCIA GUARDADA: #{@client.name}"
          return render json: { status: "success", message: "Bienvenido #{@client.name}" }
        rescue => e
          puts "❌ ERROR AL GUARDAR ASISTENCIA: #{e.message}"
          render json: { status: "error", message: e.message }, status: 500
        end
      end
    end

    huella_recibida = params[:fingerprint]
    if huella_recibida.present?
      Rails.cache.write("temp_huella_manual", huella_recibida, expires_in: 10.minutes)
      Turbo::StreamsChannel.broadcast_replace_to(
        "recepcion",
        target: "contenedor_resultado",
        partial: "clients/card_result",
        locals: { client: nil, message: "⚠️ HUELLA NO VINCULADA" }
      )
      render json: { status: "not_found", message: "Desconocida (Guardada en Cache)" }, status: :not_found
    else
      render json: { status: "error", message: "Datos incompletos" }, status: :bad_request
    end
  end

  def check_latest
    last_checkin = CheckIn.where("occurred_at > ?", 4.seconds.ago).order(created_at: :desc).first
    if last_checkin
      render json: { new_entry: true, client_id: last_checkin.client_id }
    else
      render json: { new_entry: false }
    end
  end

  def card_view
    render partial: "clients/card_result", locals: { client: @client }, layout: false
  end

  def attach_last_fingerprint
    huella_cache = Rails.cache.read("temp_huella_manual")
    if huella_cache.present?
      if @client.update(fingerprint: huella_cache)
        Rails.cache.delete("temp_huella_manual")
        redirect_to @client, notice: "✅ ¡HUELLA VINCULADA CORRECTAMENTE!"
      else
        redirect_to @client, alert: "❌ Error: #{@client.errors.full_messages.join}"
      end
    else
      redirect_to @client, alert: "⚠️ No hay huella reciente en memoria."
    end
  end

  def start_registration
    redirect_to @client, notice: "Instrucciones: 1. Pon el dedo. 2. Pulsa Vincular."
  end

  def fingerprint_status
    render json: { has_fingerprint: @client.fingerprint.present? }
  end

  # =========================================================
  # 📋 2. CRUD Y LÓGICA DE NEGOCIO
  # =========================================================
  def index
    @q = params[:q].to_s.strip
    @search_number = params[:search_number].to_s.strip
    @filter = params[:filter].presence || "name"
    @status = params[:status].to_s

    base_scope = ::Client.order(id: :desc)
    scope = base_scope

    if @search_number.present?
      scope = scope.where(id: @search_number)
      @found_client = scope.first
    end

    if @q.present?
      if @filter == "id" && @q.to_i.to_s == @q
        scope = scope.where(id: @q.to_i)
      else
        scope = scope.where("LOWER(name) LIKE ?", "%#{@q.downcase}%")
      end
    end

    if @status == "active"
      scope = scope.where.not(next_payment_on: nil).where(::Client.arel_table[:next_payment_on].gteq(Date.current))
    end

    @clients = scope
    @active_clients_count = base_scope.where("next_payment_on >= ?", Date.current).count
  end

  def show; end

  # ACTUALIZACIÓN: Aquí se calcula el siguiente socio
  def new
    @client = ::Client.new
    @next_id = (::Client.maximum(:id) || 0) + 1
  end

  def edit; end

  def create
    @client = ::Client.new(client_params)
    @client.user = current_user
    plan = params.dig(:client, :membership_type).to_s.presence

    unless plan.present?
      @client.errors.add(:membership_type, "debe seleccionarse")
      return render :new, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      if @client.next_payment_on.present?
        @client.enrolled_on ||= Date.current
      else
        @client.set_enrollment_dates!(from: Date.current)
      end
      @client.save!

      sent_price_cents = parse_money_to_cents(params[:registration_price_mxn])
      default_price    = default_registration_price_cents(plan)
      amount_cents     = (sent_price_cents && sent_price_cents > 0) ? sent_price_cents : default_price

      pm = params.dig(:client, :payment_method).presence || "cash"

      Sale.create!(user: current_user, client: @client, membership_type: plan, amount_cents: amount_cents, payment_method: pm, occurred_at: Time.current)
    end
    redirect_to @client, notice: "Cliente creado."
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity
  end

  def update
    if @client.update(client_params)
      redirect_to @client, notice: "Cliente actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_client
    @client = ::Client.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:name, :age, :weight, :height, :membership_type, :client_number, :next_payment_on, :enrolled_on, :photo)
  end

  def default_registration_price_cents(plan)
    return 0 if plan.blank?
    Client::PRICES[plan.to_s] || 0
  end

  def parse_money_to_cents(input)
    return nil if input.blank?
    s = input.to_s.gsub(/[^\d.,-]/, "")
    s = s.delete(",") if s.include?(",") && s.include?(".")
    s = s.tr(",", ".") unless s.include?(".")
    (s.to_f * 100).round
  end
end

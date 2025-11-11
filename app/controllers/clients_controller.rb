# app/controllers/clients_controller.rb
class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: [ :show, :edit, :update ] # sin :destroy

  # GET /clients
  def index
    @q      = params[:q].to_s.strip
    @filter = params[:filter].presence || "name"

    scope = ::Client.order(:id)

    if @q.present?
      case @filter
      when "id"
        # Si es número exacto, busca por ID
        if @q.to_i.to_s == @q
          scope = scope.where(id: @q.to_i)
        else
          # Si escriben algo raro, permitimos buscar por coincidencia en texto de id
          scope = scope.where("CAST(id AS TEXT) LIKE ?", "%#{@q}%")
        end
      else # "name" o cualquier otro -> nombre
        query = "%#{@q.downcase}%"
        # Si tienes extensión unaccent en PG, esto ayuda con acentos
        begin
          scope = scope.where("UNACCENT(LOWER(name)) LIKE UNACCENT(?)", query)
        rescue
          scope = scope.where("LOWER(name) LIKE ?", query)
        end
      end
    end

    # ✅ Todos los clientes en una sola página con scroll en el navegador
    # (ya NO usamos Kaminari aquí)
    @clients = scope
  end

  # GET /clients/:id
  def show
  end

  # GET /clients/new
  def new
    @client = ::Client.new
  end

  # POST /clients
  def create
    @client = ::Client.new(client_params)
    @client.user = current_user

    # Plan (day/week/month) requerido
    plan = params.dig(:client, :membership_type).to_s.presence
    unless plan.present?
      @client.errors.add(:membership_type, "debe seleccionarse")
      return render :new, status: :unprocessable_entity
    end

    amount_cents = nil

    ActiveRecord::Base.transaction do
      # Define enrolled_on y next_payment_on según el tipo de membresía
      @client.set_enrollment_dates!(from: Date.current)
      @client.save!

      # Precio enviado (opcional) o precio por defecto
      sent_price_cents = parse_money_to_cents(params[:registration_price_mxn])
      default_price    = default_registration_price_cents(plan)
      amount_cents     = (sent_price_cents && sent_price_cents > 0) ? sent_price_cents : default_price

      # Método de pago (no es campo de Client)
      pm = params.dig(:client, :payment_method).presence || params[:payment_method].presence
      payment_method = %w[cash transfer].include?(pm) ? pm : "cash"

      # Registrar venta de inscripción
      Sale.create!(
        user:            current_user,
        client:          @client,
        membership_type: plan,             # enum: day/week/month
        amount_cents:    amount_cents,
        payment_method:  payment_method,   # cash / transfer
        occurred_at:     Time.current
      )
    end

    redirect_to @client,
      notice: "Cliente creado y venta de inscripción por $#{format('%.2f', amount_cents / 100.0)}."

  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.to_sentence.presence || "Datos inválidos."
    render :new, status: :unprocessable_entity
  rescue => e
    flash.now[:alert] = "No se pudo crear el cliente: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  # GET /clients/:id/edit
  def edit
  end

  # PATCH/PUT /clients/:id
  def update
    if @client.update(client_params)
      redirect_to @client, notice: "Cliente actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_client
    @client = ::Client.find(params[:id])
  end

  def client_params
    # No incluimos :payment_method porque es solo para Sale
    params.require(:client).permit(
      :name,
      :age,
      :weight,
      :height,
      :membership_type,
      :client_number,
      :photo
    )
  end

  # Precio por defecto (centavos) según el plan
  def default_registration_price_cents(plan)
    return nil if plan.blank?

    if defined?(Client) && Client.const_defined?(:PRICES)
      Client::PRICES[plan.to_s] # "day" / "week" / "month"
    else
      # Fallback si no existe la constante
      {
        "day"   => 3_000,   # $30
        "week"  => 7_000,   # $70
        "month" => 20_000   # $200
      }[plan.to_s]
    end
  end

  # "1,200.50" / "1200,50" / "$1200.50" => centavos
  def parse_money_to_cents(input)
    s = input.to_s.strip
    return nil if s.blank?

    s = s.gsub(/[^\d.,-]/, "")

    if s.include?(",") && s.include?(".")
      # Asumimos que la coma es separador de miles -> la quitamos
      s = s.delete(",")
    else
      # Reemplaza coma por punto si es decimal
      s = s.tr(",", ".")
    end

    (s.to_f * 100).round
  end
end

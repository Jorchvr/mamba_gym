# app/controllers/clients_controller.rb
class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: [ :show, :edit, :update, :destroy ]

  # GET /clients
  def index
    @q    = params[:q].to_s.strip
    scope = ::Client.order(:id)

    if @q.present?
      if @q.to_i.to_s == @q
        scope = scope.where(id: @q.to_i)
      else
        scope = scope.where("LOWER(name) LIKE ?", "%#{@q.downcase}%")
      end
    end

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

    if @client.membership_type.present?
      @client.set_enrollment_dates!(from: Date.current)
    end

    if @client.save
      redirect_to @client, notice: "Cliente creado correctamente."
    else
      flash.now[:alert] = @client.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  # GET /clients/:id/edit
  def edit
  end

  # PATCH/PUT /clients/:id
  def update
    if @client.update(client_params)
      redirect_to @client, notice: "Cliente actualizado."
    else
      flash.now[:alert] = @client.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /clients/:id
  def destroy
    @client.destroy
    redirect_to clients_path, notice: "Cliente eliminado."
  end

  private

  def set_client
    @client = ::Client.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to clients_path, alert: "Cliente no encontrado."
  end

  def client_params
    params.require(:client).permit(
      :name,
      :age,
      :height,
      :weight,
      :membership_type,
      :enrolled_on,
      :next_payment_on,
      :photo
    )
  end
end

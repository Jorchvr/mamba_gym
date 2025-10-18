class SalesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_superuser!  # solo superusuarios ven ventas

  def index
    # Puedes filtrar por fecha si lo necesitas; por ahora listamos todo, últimas primero
    @sales = Sale
      .includes(:client, :user)
      .order(occurred_at: :desc, created_at: :desc)

    # Garantía extra: nunca nil
    @sales ||= []
  end

  def show
    @sale = Sale.includes(:client, :user).find(params[:id])
  end
end

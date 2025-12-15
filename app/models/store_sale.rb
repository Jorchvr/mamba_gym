class StoreSalesController < ApplicationController
  before_action :authenticate_user!

  # GET /store_sales
  def index
    # Muestra las ventas de tienda ordenadas por fecha
    @store_sales = StoreSale.includes(:user, :store_sale_items).order(occurred_at: :desc).limit(50)
  end

  # GET /store_sales/new
  def new
    @store_sale = StoreSale.new
    # Construimos un item vacío para que aparezca en el formulario
    @store_sale.store_sale_items.build

    # Cargamos productos activos para el select del formulario
    @products = Product.where(active: true).order(:name)
  end

  # POST /store_sales
  def create
    @store_sale = StoreSale.new(store_sale_params)
    @store_sale.user = current_user
    @store_sale.occurred_at ||= Time.current

    # Usamos una transacción para asegurar que todo se guarde o nada
    ActiveRecord::Base.transaction do
      # 1. Intentamos guardar la venta.
      # Si no hay stock, el modelo StoreSaleItem lanzará un error aquí y detendrá todo.
      @store_sale.save!

      # 2. Si se guardó (porque había stock), descontamos el inventario
      @store_sale.store_sale_items.each do |item|
        product = item.product
        if product.present?
          new_stock = product.stock - item.quantity
          product.update!(stock: new_stock)
        end
      end
    end

    # ÉXITO: Si llegamos aquí, todo salió bien
    redirect_to store_sales_path, notice: "Venta registrada correctamente."

  rescue ActiveRecord::RecordInvalid => e
    # 🛑 AQUÍ ATRAPAMOS EL ERROR 500
    # Recargamos productos para que el formulario no se rompa al volver a renderizar
    @products = Product.where(active: true).order(:name)

    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity

  rescue => e
    # Captura cualquier otro error inesperado
    @products = Product.where(active: true).order(:name)
    flash.now[:alert] = "Error inesperado: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  private

  def store_sale_params
    params.require(:store_sale).permit(
      :payment_method,
      :client_id,
      store_sale_items_attributes: [ :id, :product_id, :quantity, :unit_price_cents, :_destroy ]
    )
  end
end

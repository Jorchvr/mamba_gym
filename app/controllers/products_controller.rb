# app/controllers/products_controller.rb
class ProductsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_product, only: [ :show, :edit, :update, :destroy ]
  # Solo superusuarios pueden crear/editar/borrar; todos pueden ver el listado y el show
  before_action :require_superuser!, except: [ :index, :show ]

  # GET /products
  def index
    # Backoffice y/o catálogo sencillo
    @products = Product.order(:id)
  end

  # GET /products/:id
  def show
  end

  # GET /products/new
  def new
    @product = Product.new
  end

  # GET /products/:id/edit
  def edit
  end

  # POST /products
  def create
    @product = Product.new(product_params)
    if @product.save
      redirect_to products_path, notice: "Producto creado correctamente."
    else
      flash.now[:alert] = @product.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /products/:id
  def update
    if @product.update(product_params)
      redirect_to products_path, notice: "Producto actualizado correctamente."
    else
      flash.now[:alert] = @product.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /products/:id
  def destroy
    @product.destroy
    redirect_to products_path, notice: "Producto eliminado."
  end

  private

  def set_product
    @product = Product.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to products_path, alert: "Producto no encontrado."
  end

  # Ajusta la lista según los atributos reales de tu modelo Product
  def product_params
    params.require(:product).permit(
      :name,
      :price_cents,
      :stock,
      :description,
      :active
    )
  end
end

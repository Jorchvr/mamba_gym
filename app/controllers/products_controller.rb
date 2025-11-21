# app/controllers/products_controller.rb
class ProductsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_product, only: [ :show, :edit, :update, :destroy ]
  # Solo superusuarios pueden crear/editar/borrar; todos pueden ver el listado y el show
  before_action :require_superuser!, except: [ :index, :show ]

  # GET /products
  def index
    @q = params[:q].to_s.strip
    scope = Product.order(:id)

    if @q.present?
      scope = scope.where("LOWER(name) LIKE ?", "%#{@q.downcase}%")
    end

    @products = scope
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
      # Registramos evento de inventario si hay stock inicial
      register_inventory_event!(@product, @product.stock.to_i, note: "Stock inicial") if @product.stock.to_i > 0
      redirect_to products_path, notice: "Producto creado correctamente."
    else
      flash.now[:alert] = @product.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /products/:id
  def update
    old_stock = @product.stock.to_i

    if @product.update(product_params)
      new_stock = @product.stock.to_i
      delta = new_stock - old_stock
      # Solo registramos evento si AUMENTÓ el stock
      register_inventory_event!(@product, delta, note: "Reabastecido en edición de producto") if delta > 0
      redirect_to products_path, notice: "Producto actualizado correctamente."
    else
      flash.now[:alert] = @product.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /products/:id
  def destroy
    if @product.destroy
      redirect_to products_path, notice: "Producto eliminado correctamente."
    else
      # Cuando dependent: :restrict_with_error bloquea
      if @product.errors.details[:base].any? { |e| e[:error] == :restrict_dependent_destroy }
        msg = "No puedes eliminar este producto porque tiene movimientos de inventario o ventas registradas."
      else
        msg = "No se pudo eliminar el producto: #{@product.errors.full_messages.to_sentence}"
      end

      redirect_to products_path, alert: msg
    end

  rescue ActiveRecord::InvalidForeignKey
    # Respaldo por si el error viene directo de la base
    redirect_to products_path,
                alert: "No puedes eliminar este producto porque tiene movimientos de inventario asociados."
  end

  private

  def set_product
    @product = Product.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to products_path, alert: "Producto no encontrado."
  end

  # Permitimos los campos reales de la tabla + virtuales en MXN.
  # Los virtuales (price_mxn, cost_mxn) se convierten a *_cents en el modelo.
  def product_params
    params.require(:product).permit(
      :name,
      :stock,
      :price_cents,
      :cost_cents,
      :price_mxn,
      :cost_mxn
    )
  end

  # Crea un InventoryEvent si el modelo existe
  def register_inventory_event!(product, quantity, note:)
    return unless defined?(InventoryEvent)
    return if quantity.to_i <= 0

    InventoryEvent.create!(
      product: product,
      user: current_user,
      kind: :in,                 # reabastecimiento
      quantity: quantity.to_i,
      note: note,
      happened_at: Time.current
    )
  rescue => e
    Rails.logger.warn("[InventoryEvent] No se pudo registrar: #{e.class} #{e.message}")
  end
end

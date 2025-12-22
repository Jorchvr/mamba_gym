class ExpensesController < ApplicationController
  before_action :authenticate_user!

  def new
    @expense = Expense.new
  end

  def create
    amount = (params[:expense][:amount].to_f * 100).to_i
    @expense = Expense.new(
      description: params[:expense][:description],
      amount_cents: amount,
      user: current_user,
      occurred_at: Time.current
    )

    if @expense.save
      redirect_to authenticated_root_path, notice: "Gasto registrado correctamente."
    else
      render :new
    end
  end

  # ✅ NUEVO: Permite borrar el gasto (Venta Negativa)
  def destroy
    @expense = Expense.find(params[:id])

    # Opcional: Validar que sea del día de hoy para no alterar cortes viejos
    if @expense.occurred_at < Time.current.beginning_of_day
      redirect_to adjustments_sales_path, alert: "Solo puedes eliminar gastos del día de hoy."
      return
    end

    @expense.destroy
    redirect_to adjustments_sales_path, notice: "Gasto eliminado. El dinero ha regresado a la caja."
  end
end

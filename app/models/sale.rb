# app/models/sale.rb
require "csv"

class Sale < ApplicationRecord
  belongs_to :client, optional: true
  belongs_to :user

  # === 🟢 ACTUALIZADO: Agregados los nuevos planes ===
  # IMPORTANTE: El orden/números deben coincidir con lo que pongas en Client
  enum :membership_type, {
    day: 0,
    week: 1,
    month: 2,
    couple: 3,
    semester: 4,
    visit: 5,
    promo: 6
  }, prefix: :membership

  # === 🟢 ACTUALIZADO: Agregada la opción 'card' (Tarjeta) ===
  # Mantenemos transfer por si tienes datos viejos, y agregamos card al final
  enum :payment_method, {
    cash: 0,
    transfer: 1,
    card: 2
  }, prefix: :paid

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :payment_method, presence: true
  validates :user, presence: true

  # ===== Defaults y scopes =====
  before_validation :ensure_occurred_at

  scope :on_date, ->(date) {
    from = date.beginning_of_day
    to   = date.end_of_day
    where("COALESCE(occurred_at, created_at) BETWEEN ? AND ?", from, to)
  }

  scope :today, -> { on_date(Time.zone.today) }

  def amount
    amount_cents.to_i / 100.0
  end

  # ===== Exportador CSV =====
  def self.to_csv(records)
    CSV.generate(headers: true) do |csv|
      csv << [
        "ID",
        "Fecha/Hora",
        "Tipo Membresía",
        "Método de pago",
        "Monto (centavos)",
        "Monto",
        "Usuario",
        "Cliente ID",
        "Cliente Nombre"
      ]

      records.find_each do |s|
        ts = (s.occurred_at || s.created_at)&.in_time_zone&.strftime("%Y-%m-%d %H:%M:%S")
        csv << [
          s.id,
          ts,
          s.membership_type,
          s.payment_method,
          s.amount_cents,
          ("%.2f" % s.amount),
          s.user&.email || s.user&.id,
          s.client_id,
          s.client&.name
        ]
      end
    end
  end

  private

  def ensure_occurred_at
    self.occurred_at ||= Time.current
  end
end

# app/models/sale.rb
require "csv"

class Sale < ApplicationRecord
  belongs_to :client, optional: true
  belongs_to :user

  enum :membership_type, { day: 0, week: 1, month: 2 }, prefix: :membership
  enum :payment_method,  { cash: 0, transfer: 1 },       prefix: :paid

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :payment_method, presence: true
  validates :user, presence: true
  # NOTA: dejamos occurred_at como opcional para no romper datos antiguos, pero lo rellenamos automáticamente.
  # validates :occurred_at, presence: true  # <- ya no es obligatorio estrictamente

  # ===== Defaults y scopes =====
  # Asegura que siempre tengamos occurred_at poblado al crear/guardar
  before_validation :ensure_occurred_at

  # Ventas en un día usando COALESCE(occurred_at, created_at)
  scope :on_date, ->(date) {
    from = date.beginning_of_day
    to   = date.end_of_day
    where("COALESCE(occurred_at, created_at) BETWEEN ? AND ?", from, to)
  }

  # Mantenemos el scope today, pero ahora usa on_date
  scope :today, -> { on_date(Time.zone.today) }

  def amount
    amount_cents.to_i / 100.0
  end

  # ===== Exportador CSV para "Excel" =====
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

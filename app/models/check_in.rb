class CheckIn < ApplicationRecord
  belongs_to :client
  # Importante: optional: true para que no falle si lo crea el lector de huellas
  belongs_to :user, optional: true

  validates :occurred_at, presence: true

  before_validation :ensure_occurred_at

  scope :today, -> { where(occurred_at: Time.zone.today.all_day) }

  # 👇 ESTA ES LA MAGIA (Turbo Streams)
  # Dice: "Al crear, actualiza el cuadro 'contenedor_resultado' usando el archivo '_card_result'"
  after_create_commit do
    broadcast_replace_to "recepcion",
      target: "contenedor_resultado",
      partial: "clients/card_result",
      locals: { client: client }
  end

  private

  def ensure_occurred_at
    self.occurred_at ||= Time.current
  end
end
